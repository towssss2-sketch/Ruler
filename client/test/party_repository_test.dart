import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/case_detail.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/case_detail_wire.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'api_fixture.dart';

Map<String, Object?> detailFixture() => {
  'id': 'case-1',
  'caseNo': '(2026)虚构民初1号',
  'cause': '虚构案由',
  'court': '虚构法院',
  'stage': 'FIRST_INSTANCE',
  'status': 'ACTIVE',
  'feeStatus': 'UNPAID',
  'documentCount': 3,
  'pendingTaskCount': 2,
  'notes': '虚构备注',
  'fee': '12.34',
  'parties': [
    {
      'id': 'party-1',
      'name': '虚构甲',
      'role': 'PLAINTIFF',
      'phone': '虚构电话',
      'idCard': null,
      'address': '虚构地址',
    },
  ],
};

void main() {
  test('解析详情与不可变名单，保留角色、可选值、费用和统计', () {
    final detail = readCaseDetail(detailFixture());
    expect(detail.parties.single.phone, '虚构电话');
    expect(detail.parties.single.idCard, isNull);
    expect(detail.documentCount, 3);
    expect(detail.pendingTaskCount, 2);
    expect(detail.fee, '12.34');
    expect(() => detail.parties.clear(), throwsUnsupportedError);
  });
  test('损坏详情、未知枚举、重复身份和错误统计均安全拒绝', () {
    final row =
        (detailFixture()['parties'] as List).single as Map<String, Object?>;
    for (final patch in <Map<String, Object?>>[
      {'stage': 'UNKNOWN'},
      {'feeStatus': 'UNKNOWN'},
      {'documentCount': -1},
      {'pendingTaskCount': '2'},
      {'notes': 12},
      {'parties': 'not-a-list'},
      {
        'parties': [row, row],
      },
      {
        'parties': [
          {...row, 'role': 'OWNER'},
        ],
      },
      {
        'parties': [
          {...row, 'phone': 123},
        ],
      },
      {
        'parties': [
          {...row, 'id': null},
        ],
      },
    ]) {
      expect(
        () => readCaseDetail({...detailFixture(), ...patch}),
        throwsA(
          isA<ApiFailure>().having((e) => e.message, 'safe', '服务响应格式异常。'),
        ),
      );
    }
  });
  test('名单全量验证覆盖 0/100/101、屏幕外空姓名、超长可选资料和重复 id', () {
    const valid = CaseParty(name: '虚构', role: 'PLAINTIFF');
    expect(validateParties([]), isNotNull);
    expect(validateParties(List.filled(100, valid)), isNull);
    expect(validateParties(List.filled(101, valid)), isNotNull);
    expect(
      validateParties([valid, const CaseParty(name: ' ', role: 'DEFENDANT')]),
      contains('第 2 位'),
    );
    expect(
      validateParties([
        CaseParty(name: '虚构', role: 'PLAINTIFF', phone: 'x' * 65),
      ]),
      isNotNull,
    );
    expect(
      validateParties([valid.identified('one'), valid.identified('one')]),
      isNotNull,
    );
  });
  patchContract();
  memoryContract();
}

void patchContract() {
  test('真实仓库只 PATCH 当事人、保留旧 id/省略新 id，空可选值写 null', () async {
    final requests = <RequestOptions>[];
    final session = ApiSession(
      'https://example.invalid',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((request) {
          if (request.path == '/auth/login') return reply(tokens());
          requests.add(request);
          return reply(
            request.method == 'GET' ? detailFixture() : {'id': 'case-1'},
          );
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final repository = ApiRepository(session);
    final original = await repository.caseDetail('one/two');
    expect(original.parties.single.id, 'party-1');
    await repository.saveParties('one/two', [
      const CaseParty(id: 'party-1', name: '虚构甲改', role: 'DEFENDANT'),
      const CaseParty(name: '虚构乙', role: 'THIRD_PARTY', address: '虚构地址乙'),
    ]);
    expect(requests.map((r) => r.method), ['GET', 'PATCH']);
    expect(requests.last.path, '/cases/one%2Ftwo');
    final payload = requests.last.data as Map;
    expect(payload.keys, ['parties']);
    final parties = payload['parties'] as List;
    expect(parties.first['id'], 'party-1');
    expect(parties.first['phone'], isNull);
    expect((parties.last as Map).containsKey('id'), isFalse);
    await expectLater(
      repository.saveParties('one/two', []),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests.length, 2);
  });
}

void memoryContract() {
  test('离线当事人身份稳定，移除及清空保留关联数据，外案 id/重复身份拒绝', () async {
    final repository = MemoryExperience();
    final id = await repository.create('(2026)虚构民初1号', '虚构', '虚构');
    final other = await repository.create('(2026)虚构民初2号', '虚构', '虚构');
    await repository.addTask(id, '虚构任务');
    await repository.addSample(id);
    await repository.saveParties(id, [
      const CaseParty(name: '虚构甲', role: 'PLAINTIFF', phone: '虚构电话'),
    ]);
    final before = (await repository.load()).last;
    final partyId = before.parties.single.id!;
    await expectLater(
      repository.saveParties(other, before.parties),
      throwsException,
    );
    await repository.saveParties(id, [
      CaseParty(id: partyId, name: '虚构甲改', role: 'DEFENDANT'),
      const CaseParty(name: '虚构乙', role: 'THIRD_PARTY'),
    ]);
    final after = (await repository.load()).last;
    expect(after.parties.first.id, partyId);
    expect(after.parties.first.phone, isNull);
    expect(before.parties.single.phone, '虚构电话');
    expect(after.tasks.single.id, before.tasks.single.id);
    expect(after.files.single.id, before.files.single.id);
    await repository.saveParties(id, [after.parties.last]);
    expect((await repository.load()).last.parties.single.name, '虚构乙');
    await expectLater(
      repository.saveParties(id, [after.parties.last, after.parties.last]),
      throwsException,
    );
    await repository.remove(id);
    await expectLater(
      repository.saveParties(id, [after.parties.last]),
      throwsException,
    );
    expect((await repository.load()).single.parties, isEmpty);
  });
}
