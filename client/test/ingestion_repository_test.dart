import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/ingestion_provider.dart';
import 'package:ruler_client/domain/ingestion.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_ingestion.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/ingestion_wire.dart';
import 'api_fixture.dart';
import 'ingestion_fixture.dart';

void main() {
  test('文字边界保留内部空白，规范换行，拒绝空白、超长及零字节', () {
    expect(normalizeIngestionText(' 虚构 A  B\r\n下一行\r结束 '), '虚构 A  B\n下一行\n结束');
    expect(ingestionTextError('😀' * 10000), isNull);
    for (final text in [' ', '字' * 10001, '虚构\u0000']) {
      expect(ingestionTextError(text), isNotNull);
    }
  });
  protocol();
  pageProtocol();
  requestContract();
  memory();
}

void protocol() {
  test('协议状态、日期、正文、分页或重复 ID 损坏整体拒绝', () {
    for (final patch in <Map<String, Object?>>[
      {'status': 'OTHER'},
      {'channel': 'OTHER'},
      {'receivedAt': '2026-02-30T00:00:00.000Z'},
      {'preview': ''},
      {'preview': '字' * 201},
      {'id': null},
    ]) {
      expect(
        () => readIngestionItem({...ingestionRow(), ...patch}),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(
      () => readIngestionItem({
        ...ingestionRow(),
        'rawContent': null,
      }, detail: true),
      throwsA(isA<ApiFailure>()),
    );
    for (final value in [
      {'id': '1', 'status': 'UNKNOWN', 'duplicate': true},
      {'id': '1', 'status': 'IGNORED', 'duplicate': false},
      {'id': '1', 'status': 'PENDING_MATCH', 'duplicate': 'false'},
    ]) {
      expect(() => readIngestionReceipt(value), throwsA(isA<ApiFailure>()));
    }
  });
}

void pageProtocol() {
  test('分页一致性、未知待定状态与重复 ID 整体拒绝', () {
    for (final patch in <Map<String, Object?>>[
      {'total': -1},
      {'total': 2},
      {'page': 1.0},
      {'page': 2},
      {'pageSize': 20.0},
      {'pageSize': 10},
      {
        'items': [ingestionRow(), ingestionRow()],
        'total': 2,
      },
      {
        'items': [
          {...ingestionRow(), 'status': 'IGNORED'},
        ],
      },
    ]) {
      expect(
        () => readIngestionPage(
          {
            ...ingestionPage([ingestionRow()]),
            ...patch,
          },
          1,
          false,
        ),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(
      readIngestionPage(ingestionPage([], page: 2, total: 1), 2, false).items,
      isEmpty,
    );
    expect(
      readIngestionPage(
        ingestionPage([
          {...ingestionRow(), 'status': 'IGNORED'},
        ]),
        1,
        true,
      ).items.single.status,
      'IGNORED',
    );
  });
}

void requestContract() {
  test('真实 API 仓库只发送正文或分页，路径编码，忽略确认值必须为真', () async {
    final requests = <RequestOptions>[];
    var ignored = true;
    final session = ApiSession(
      'http://127.0.0.1:3000',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((r) {
          requests.add(r);
          if (r.path == '/auth/login') return reply(tokens());
          if (r.path == '/ingestion/wechat') {
            return reply({
              'id': '1',
              'status': 'PENDING_MATCH',
              'duplicate': false,
            });
          }
          if (r.path.endsWith('/ignore')) return reply({'ignored': ignored});
          if (r.path.endsWith('/logs') || r.path.endsWith('/pending')) {
            return reply(ingestionPage([], page: 2));
          }
          return reply(ingestionRow());
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final repo = ApiIngestion(session);
    await repo.receive(' 虚构\r\n文字 ');
    expect(requests.last.data, {'rawContent': '虚构\n文字'});
    await repo.list(page: 2, history: true);
    expect(requests.last.path, '/ingestion/logs');
    expect(requests.last.queryParameters, {'page': 2, 'pageSize': 20});
    await repo.ignore('fictional/id');
    expect(requests.last.path, '/ingestion/fictional%2Fid/ignore');
    expect(requests.last.data, isEmpty);
    ignored = false;
    await expectLater(repo.ignore('fictional/id'), throwsA(isA<ApiFailure>()));
    final before = requests.length;
    await expectLater(repo.receive(' '), throwsA(isA<ApiFailure>()));
    expect(requests.length, before);
  });
}

void memory() {
  test('离线 Provider 保存、重复、忽略、全页历史与应用生命周期隔离', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repo = container.read(experienceIngestionProvider);
    final first = await repo.receive(' 虚构\r\n文字 ');
    expect((await repo.receive('虚构\n文字')).id, first.id);
    for (var i = 0; i < 21; i++) {
      await repo.receive('虚构$i');
    }
    expect((await repo.list()).total, 22);
    expect((await repo.list(page: 2)).items.length, 2);
    await repo.ignore(first.id);
    await repo.ignore(first.id);
    expect((await repo.list()).total, 21);
    expect((await repo.list(history: true)).total, 22);
    expect((await repo.detail(first.id)).rawContent, '虚构\n文字');
    final duplicate = await repo.receive('虚构\n文字');
    expect(duplicate.duplicate, true);
    expect(duplicate.status, 'IGNORED');
    expect(container.read(experienceIngestionProvider), same(repo));
    final other = ProviderContainer();
    addTearDown(other.dispose);
    expect((await other.read(experienceIngestionProvider).list()).total, 0);
    await expectLater(repo.detail('missing'), throwsA(isA<ApiFailure>()));
  });
}
