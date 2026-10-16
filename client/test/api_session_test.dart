import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'api_fixture.dart';

void main() {
  test('地址拒绝明文远端、URL 凭据、路径及查询参数', () {
    for (final value in [
      'http://example.invalid',
      'https://name:secret@example.invalid',
      'https://example.invalid/path',
      'https://example.invalid?key=x',
      'https://example.invalid#x',
      'file:///tmp/a',
      '//example.invalid',
    ]) {
      expect(() => validateApiOrigin(value), throwsA(isA<ApiFailure>()));
    }
    expect(
      validateApiOrigin('http://127.0.0.1:9001/'),
      'http://127.0.0.1:9001',
    );
    expect(
      validateApiOrigin('https://example.invalid'),
      'https://example.invalid',
    );
  });
  registerScenario2();
  registerScenario3();
  registerScenario4();
  registerScenario5();
  registerScenario6();
  registerScenario7();
  failureTests();
}

void registerScenario2() {
  test('并发 401 只轮换一次，所有请求携带新凭据恢复', () async {
    var refreshes = 0;
    var reads = 0;
    final gate = Completer<ResponseBody>();
    final dio = Dio()
      ..httpClientAdapter = TestAdapter((request) {
        if (request.path == '/auth/login') return reply(tokens());
        if (request.path == '/auth/refresh') {
          refreshes++;
          return gate.future;
        }
        if (request.headers['Authorization'] == 'Bearer fictional-access-one') {
          return reply(null, 401);
        }
        reads++;
        return reply({'ok': true});
      });
    final session = ApiSession('https://example.invalid', dio: dio);
    addTearDown(session.close);
    await session.login('test@example.invalid', 'fictional-password');
    final requests = List.generate(6, (_) => session.request('GET', '/cases'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(refreshes, 1);
    gate.complete(reply(tokens('two')));
    await Future.wait(requests);
    expect(refreshes, 1);
    expect(reads, 6);
  });
}

void registerScenario3() {
  test('晚到的旧 401 复用已轮换令牌，不再次刷新', () async {
    var refreshes = 0;
    final delayed = Completer<ResponseBody>();
    var oldReads = 0;
    final dio = Dio()
      ..httpClientAdapter = TestAdapter((request) {
        if (request.path == '/auth/login') return reply(tokens());
        if (request.path == '/auth/refresh') {
          refreshes++;
          return reply(tokens('two'));
        }
        if (request.headers['Authorization'] == 'Bearer fictional-access-one') {
          oldReads++;
          return oldReads == 1 ? delayed.future : reply(null, 401);
        }
        return reply({'ok': true});
      });
    final session = ApiSession('https://example.invalid', dio: dio);
    addTearDown(session.close);
    await session.login('test@example.invalid', 'fictional-password');
    final first = session.request('GET', '/cases');
    await session.request('GET', '/cases');
    delayed.complete(reply(null, 401));
    await first;
    expect(refreshes, 1);
  });
}

void failureTests() {
  for (final failure in ['timeout', '401', 'malformed']) {
    test('刷新 $failure 清空会话且不重试旧凭据', () async {
      var refreshes = 0;
      var expired = 0;
      final dio = Dio()
        ..httpClientAdapter = TestAdapter((request) {
          if (request.path == '/auth/login') return reply(tokens());
          if (request.path != '/auth/refresh') return reply(null, 401);
          refreshes++;
          if (failure == 'timeout') {
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
              message: 'unsafe-private-message',
            );
          }
          return failure == '401' ? reply(null, 401) : reply({'invalid': true});
        });
      final session = ApiSession(
        'https://example.invalid',
        dio: dio,
        onExpired: () => expired++,
      );
      addTearDown(session.close);
      await session.login('test@example.invalid', 'fictional-password');
      for (var i = 0; i < 2; i++) {
        await expectLater(
          session.request('GET', '/cases'),
          throwsA(
            isA<ApiFailure>().having((e) => e.sessionEnded, 'ended', true),
          ),
        );
      }
      expect(refreshes, 1);
      expect(expired, 1);
      expect(session.authenticated, false);
    });
  }
}

void registerScenario4() {
  test('写入超时不自动重发，提示不泄露响应原文', () async {
    var writes = 0;
    final dio = Dio()
      ..httpClientAdapter = TestAdapter((request) {
        if (request.path == '/auth/login') return reply(tokens());
        writes++;
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
          message: 'unsafe-private-message',
        );
      });
    final session = ApiSession('https://example.invalid', dio: dio);
    addTearDown(session.close);
    await session.login('test@example.invalid', 'fictional-password');
    await expectLater(
      session.request('POST', '/cases', data: {'caseNo': 'fictional'}),
      throwsA(
        isA<ApiFailure>().having((e) => e.message, 'safe', contains('结果未确认')),
      ),
    );
    expect(writes, 1);
    expect(session.authenticated, true);
  });
}

void registerScenario5() {
  test('关闭后晚到的登录响应不能恢复会话', () async {
    final pending = Completer<ResponseBody>();
    final session = ApiSession(
      'https://example.invalid',
      dio: Dio()..httpClientAdapter = TestAdapter((_) => pending.future),
    );
    final login = session.login('test@example.invalid', 'fictional-password');
    final assertion = expectLater(login, throwsA(isA<ApiFailure>()));
    await Future<void>.delayed(Duration.zero);
    session.close();
    pending.complete(reply(tokens()));
    await assertion;
    expect(session.authenticated, false);
  });
}

void registerScenario6() {
  test('登出失败仍清本地，明确远端吊销未确认', () async {
    final session = ApiSession(
      'https://example.invalid',
      dio: Dio()
        ..httpClientAdapter = TestAdapter(
          (request) => request.path == '/auth/login'
              ? reply(tokens())
              : reply(null, 503),
        ),
    );
    await session.login('test@example.invalid', 'fictional-password');
    await expectLater(
      session.logout(),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'safe',
          contains('服务端退出尚未确认'),
        ),
      ),
    );
    expect(session.authenticated, false);
  });
}

void registerScenario7() {
  test('403 不触发刷新且不展示服务端原文', () async {
    var requests = 0;
    final session = ApiSession(
      'https://example.invalid',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((request) {
          requests++;
          return request.path == '/auth/login'
              ? reply(tokens())
              : reply(null, 403);
        }),
    );
    addTearDown(session.close);
    await session.login('test@example.invalid', 'fictional-password');
    await expectLater(
      session.request('GET', '/cases/foreign'),
      throwsA(
        isA<ApiFailure>().having((e) => e.message, 'safe', startsWith('无权访问')),
      ),
    );
    expect(requests, 2);
  });
}
