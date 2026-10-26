import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/domain/ingestion_preview.dart';
import 'package:ruler_client/infrastructure/api_ingestion_preview.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/memory_ingestion.dart';
import 'package:ruler_client/infrastructure/memory_ingestion_preview.dart';
import 'api_fixture.dart';
import 'ingestion_preview_fixture.dart';

class PreviewProtocol {
  Object? response = previewRow();
  int status = 201;
  final requests = <RequestOptions>[];
  late final session = ApiSession(
    'http://127.0.0.1:3000',
    dio: Dio()
      ..httpClientAdapter = TestAdapter((r) {
        requests.add(r);
        return r.path == '/auth/login'
            ? reply(tokens())
            : reply(response, status);
      }),
  );
  late final api = ApiIngestionPreview(session);
  Future<void> login() =>
      session.login('fictional@example.invalid', 'fictional-password');
}

void main() {
  test('守卫401只刷新一次，重试保留提取等待时间，刷新请求沿用原超时', () async {
    var previews = 0;
    final seen = <RequestOptions>[];
    final session = ApiSession(
      'http://127.0.0.1:3000',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((r) {
          seen.add(r);
          if (r.path == '/auth/login' || r.path == '/auth/refresh') {
            return reply(tokens(r.path));
          }
          return ++previews == 1 ? reply(null, 401) : reply(previewRow());
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    expect((await ApiIngestionPreview(session).preview('id')).text, isNotNull);
    expect(previews, 2);
    expect(
      seen
          .where((r) => r.path.endsWith('/preview'))
          .every((r) => r.receiveTimeout == const Duration(seconds: 40)),
      true,
    );
    expect(
      seen.singleWhere((r) => r.path == '/auth/refresh').receiveTimeout,
      const Duration(seconds: 20),
    );
  });
  test('真实协议路径编码、空请求体、独立等待时间与待确认建议，不修改其他请求超时', () async {
    final f = PreviewProtocol();
    addTearDown(f.session.close);
    await f.login();
    final result = await f.api.preview('in/box');
    expect(f.requests.last.path, '/ingestion/in%2Fbox/preview');
    expect(f.requests.last.method, 'POST');
    expect(f.requests.last.data, isEmpty);
    expect(f.requests.last.receiveTimeout, const Duration(seconds: 40));
    expect(f.requests.first.receiveTimeout, const Duration(seconds: 20));
    expect(result.text, '法律服务合同\n仅为虚构联调正文。');
    expect(result.suggestion!.category, 'SERVICE_CONTRACT');
    expect(result.suggestion!.caseNumbers, ['(2026)虚构民初90号']);
    expect(
      () => result.suggestion!.caseNumbers.add('fake'),
      throwsUnsupportedError,
    );
  });
  test('成功响应的正文、候选、确认标记、状态冲突与过量案号严格拒绝，不猜测默认值', () async {
    final f = PreviewProtocol();
    addTearDown(f.session.close);
    await f.login();
    for (final change in [
      {'attemptId': ''},
      {'attemptId': 'bad'},
      {'extraction': null},
      {
        'extraction': {'state': 'TEXT', 'text': ''},
      },
      {
        'extraction': {'state': 'TEXT', 'text': ' '},
      },
      {
        'extraction': {'state': 'TEXT', 'text': 'x' * 100001},
      },
      {
        'extraction': {'state': 'UNKNOWN', 'text': 'private'},
      },
      {
        'extraction': {'state': 'TEXT', 'text': 'private', 'reason': 'TIMEOUT'},
      },
      {'suggestion': null},
    ]) {
      f.response = {...previewRow(), ...change};
      await expectLater(f.api.preview('id'), throwsA(isA<ApiFailure>()));
    }
    for (final change in [
      {'category': 'BAD'},
      {'category': null},
      {'requiresConfirmation': false},
      {'requiresConfirmation': null},
      {'ruleVersion': 'unknown'},
      {'reason': 'NO_TITLE'},
      {'caseNumbers': null},
      {
        'caseNumbers': ['bad'],
      },
      {
        'caseNumbers': [1],
      },
      {'caseNumbers': List.filled(11, '(2026)虚构民初1号')},
      {
        'caseNumbers': ['(2026)虚构民初1号', '(2026)虚构民初1号'],
      },
      {'caseNumbersTruncated': true},
      {'caseNumbersTruncated': 'false'},
    ]) {
      final row = previewRow();
      row['suggestion'] = {
        ...row['suggestion']! as Map<String, Object?>,
        ...change,
      };
      f.response = row;
      await expectLater(f.api.preview('id'), throwsA(isA<ApiFailure>()));
    }
  });
  test('全部降级原因严格解析，可重试仅超时/暂不可用；坏结果不透传部分正文', () async {
    final f = PreviewProtocol();
    addTearDown(f.session.close);
    await f.login();
    for (final reason in previewReasons.keys) {
      f.response = {
        ...previewRow(),
        'extraction': {
          'state': 'MANUAL_REQUIRED',
          'reason': reason,
          'retryable': ['TIMEOUT', 'UNAVAILABLE'].contains(reason),
        },
        'suggestion': null,
      };
      final result = await f.api.preview('id');
      expect(result.reason, reason);
      expect(result.text, isNull);
    }
    for (final result in [
      {'state': 'MANUAL_REQUIRED', 'reason': 'UNKNOWN', 'retryable': false},
      {'state': 'MANUAL_REQUIRED', 'reason': 'TIMEOUT', 'retryable': false},
      {'state': 'MANUAL_REQUIRED', 'reason': 'NO_TEXT', 'retryable': true},
      {'state': 'MANUAL_REQUIRED', 'reason': 'NO_TEXT', 'retryable': null},
      {
        'state': 'MANUAL_REQUIRED',
        'reason': 'NO_TEXT',
        'retryable': false,
        'text': 'private',
      },
    ]) {
      f.response = {...previewRow(), 'extraction': result, 'suggestion': null};
      await expectLater(f.api.preview('id'), throwsA(isA<ApiFailure>()));
    }
    f.response = {
      ...previewRow(),
      'extraction': {
        'state': 'MANUAL_REQUIRED',
        'reason': 'NO_TEXT',
        'retryable': false,
      },
    };
    await expectLater(f.api.preview('id'), throwsA(isA<ApiFailure>()));
  });
  test('冲突/未知标题可以无分类，案号截断明确，汉字扩展区与后端一致', () async {
    final f = PreviewProtocol();
    addTearDown(f.session.close);
    await f.login();
    for (final reason in ['NO_TITLE', 'CONFLICTING_TITLES']) {
      final row = previewRow();
      row['suggestion'] = {
        ...row['suggestion']! as Map<String, Object?>,
        'category': null,
        'reason': reason,
        'caseNumbers': ['(2026)𠀀民初1号'],
      };
      f.response = row;
      expect((await f.api.preview('id')).suggestion!.category, isNull);
    }
    final row = previewRow();
    row['suggestion'] = {
      ...row['suggestion']! as Map<String, Object?>,
      'caseNumbers': List.generate(10, (i) => '(2026)虚构民初$i号'),
      'caseNumbersTruncated': true,
    };
    f.response = row;
    expect((await f.api.preview('id')).suggestion!.truncated, true);
  });
  test('网络/限流失败不自动重复提交，关闭会话拒绝晚到正文', () async {
    final f = PreviewProtocol();
    addTearDown(f.session.close);
    await f.login();
    for (final status in [403, 429, 503]) {
      f.status = status;
      final count = f.requests.length;
      await expectLater(f.api.preview('id'), throwsA(isA<ApiFailure>()));
      expect(f.requests.length, count + 1);
    }
    final gate = Completer<void>();
    final session = ApiSession(
      'http://127.0.0.1:3000',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((r) async {
          if (r.path == '/auth/login') return reply(tokens());
          await gate.future;
          return reply(previewRow());
        }),
    );
    await session.login('fictional@example.invalid', 'fictional-password');
    final pending = expectLater(
      ApiIngestionPreview(session).preview('id'),
      throwsA(isA<ApiFailure>()),
    );
    await Future<void>.delayed(Duration.zero);
    session.close();
    gate.complete();
    await pending;
  });
  test('离线是固定虚构正文，预览不改变归档/忽略状态，纯文字和未知记录拒绝', () async {
    final inbox = MemoryIngestion(),
        api = MemoryIngestionPreview(MemoryIngestion());
    await expectLater(api.preview('missing'), throwsA(isA<ApiFailure>()));
    final memory = MemoryIngestionPreview(inbox),
        item = await inbox.addFileExample();
    final first = await memory.preview(item.id);
    expect(first.text, contains('没有读取或解析真实文件'));
    expect(first.suggestion!.category, 'SERVICE_CONTRACT');
    expect((await inbox.detail(item.id)).status, 'PENDING_MATCH');
    await inbox.ignore(item.id);
    expect((await memory.preview(item.id)).attemptId, isNot(first.attemptId));
    expect((await inbox.detail(item.id)).status, 'IGNORED');
    final text = await inbox.receive('虚构纯文字');
    await expectLater(memory.preview(text.id), throwsA(isA<ApiFailure>()));
  });
}
