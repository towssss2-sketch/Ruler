import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_ingestion_assignment.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'api_fixture.dart';
import 'ingestion_assign_fixture.dart';

const number = '(2026)虚构民初90号';
Map<String, Object?> matchedRow() => {
  'id': '00000000-0000-4000-8000-000000000001',
  'caseNo': number,
  'court': '虚构法院',
  'cause': '虚构案由',
  'stage': 'SECOND_INSTANCE',
  'status': 'CLOSED',
};
Map<String, Object?> matchedPage() => {
  'items': [matchedRow()],
  'total': 1,
  'page': 1,
  'pageSize': 20,
  'group': 'owned',
  'collaborationEnabled': false,
};

class MatchApi {
  Object? data = matchedPage();
  int status = 200;
  final requests = <RequestOptions>[];
  Completer<void>? gate;
  late final session = ApiSession(
    'http://127.0.0.1:3000',
    dio: Dio()
      ..httpClientAdapter = TestAdapter((r) async {
        requests.add(r);
        if (r.path == '/auth/login' || r.path == '/auth/refresh') {
          return reply(tokens());
        }
        await gate?.future;
        return reply(data, status);
      }),
  );
  late final api = ApiIngestionAssignment(session, ApiRepository(session));
  Future<void> login() =>
      session.login('fictional@example.invalid', 'fictional-password');
}

void main() {
  test('完整案号发精确条件，统一括号空白，保留结案状态和不可变结果', () async {
    final f = MatchApi();
    addTearDown(f.session.close);
    await f.login();
    final page = await f.api.cases(caseNo: ' （2026） 虚构民初90号 ');
    expect(f.requests.last.method, 'GET');
    expect(f.requests.last.path, '/cases');
    expect(f.requests.last.queryParameters, {
      'caseNo': number,
      'page': 1,
      'pageSize': 20,
    });
    expect(page.items.single.status, 'CLOSED');
    expect(page.items.single.stage, 'SECOND_INSTANCE');
    expect(() => page.items.clear(), throwsUnsupportedError);
    f.data = {...matchedPage(), 'items': [], 'page': 2};
    expect((await f.api.cases(caseNo: number, page: 2)).items, isEmpty);
    expect(f.requests.last.queryParameters['page'], 2);
    final supplementary = '(2026)${'𠀀' * 60}号';
    f.data = {
      ...matchedPage(),
      'items': [
        {...matchedRow(), 'caseNo': supplementary},
      ],
    };
    expect(
      (await f.api.cases(caseNo: supplementary)).items.single.caseNo,
      supplementary,
    );
  });
  test('非法空案号或页码在请求前拒绝；不把空条件当全部案件', () async {
    final f = MatchApi();
    addTearDown(f.session.close);
    await f.login();
    for (final value in ['', ' ', '90', '%', 'null', '(2026)${'民' * 61}号']) {
      await expectLater(f.api.cases(caseNo: value), throwsA(isA<ApiFailure>()));
    }
    for (final page in [0, -1, 10000]) {
      await expectLater(
        f.api.cases(caseNo: number, page: page),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(f.requests.length, 1);
  });
  test('拒绝非同号、越界分页、错误分组、重复身份及残缺摘要，空结果仍明确返回', () async {
    final f = MatchApi();
    addTearDown(f.session.close);
    await f.login();
    final badPages = [
      {'items': null},
      {'total': -1},
      {'total': 1.5},
      {'total': 2},
      {'page': 2},
      {'pageSize': 10},
      {'group': 'collaborated'},
      {'collaborationEnabled': true},
      {
        'total': 2,
        'items': [matchedRow(), matchedRow()],
      },
    ];
    for (final change in badPages) {
      f.data = {...matchedPage(), ...change};
      await expectLater(
        f.api.cases(caseNo: number),
        throwsA(isA<ApiFailure>()),
      );
    }
    for (final change in [
      {'caseNo': '(2026)虚构民初190号'},
      {'caseNo': '（2026）虚构民初90号'},
      {'id': 'bad'},
      {'court': ''},
      {'cause': null},
      {'stage': 'bad'},
      {'status': 'bad'},
      {'court': '虚' * 129},
      {'cause': ' '},
    ]) {
      f.data = {
        ...matchedPage(),
        'items': [
          {...matchedRow(), ...change},
        ],
      };
      await expectLater(
        f.api.cases(caseNo: number),
        throwsA(isA<ApiFailure>()),
      );
    }
    f.data = {...matchedPage(), 'items': [], 'total': 0};
    expect((await f.api.cases(caseNo: number)).total, 0);
  });
  test('服务错误不伪装成未命中；关闭会话丢弃晚到匹配结果', () async {
    final f = MatchApi();
    addTearDown(f.session.close);
    await f.login();
    for (final status in [403, 429, 503]) {
      f.status = status;
      final before = f.requests.length;
      await expectLater(
        f.api.cases(caseNo: number),
        throwsA(isA<ApiFailure>()),
      );
      expect(f.requests.length, before + 1);
    }
    f.status = 200;
    f.gate = Completer<void>();
    final pending = f.api.cases(caseNo: number);
    final rejected = expectLater(
      pending,
      throwsA(
        isA<ApiFailure>().having((e) => e.sessionEnded, 'sessionEnded', true),
      ),
    );
    f.session.close();
    f.gate!.complete();
    await rejected;
  });
  test('离线精确条件作用于全量内存再分页，排除案由引用，删除后重查不返回', () async {
    final f = AssignmentFixture();
    await f.prepare();
    for (var i = 0; i < 20; i++) {
      await f.experience.create(number, '虚构同号', '虚构法院$i');
    }
    await f.experience.create('(2026)虚构民初190号', number, '虚构法院');
    final a = await f.repository.cases(caseNo: '（2026）虚构民初90号');
    final b = await f.repository.cases(caseNo: number, page: 2);
    expect(a.total, 21);
    expect(a.items.length, 20);
    expect(b.items.length, 1);
    expect(
      {...a.items.map((e) => e.id), ...b.items.map((e) => e.id)}.length,
      21,
    );
    await f.experience.remove(f.caseId);
    expect((await f.repository.cases(caseNo: number)).total, 20);
    expect((await f.repository.cases(caseNo: number, keyword: '不存在')).total, 0);
    await expectLater(
      f.repository.cases(caseNo: ''),
      throwsA(isA<ApiFailure>()),
    );
  });
}
