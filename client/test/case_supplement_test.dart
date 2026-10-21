import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/case_detail.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/case_detail_wire.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'api_fixture.dart';
import 'party_repository_test.dart' show detailFixture;

void main() {
  amountContract();
  textContract();
  wireContract();
  repositoryContract();
  memoryContract();
}

void amountContract() {
  test('金额精确规范化、零与空值区别、上下界和非法表达式', () {
    for (final pair in {
      '0': '0.00',
      '12': '12.00',
      ' 12.3 ': '12.30',
      '999999999999.99': '999999999999.99',
    }.entries) {
      final value = CaseSupplement(fee: pair.key);
      expect(value.error, isNull);
      expect(value.normalized.fee, pair.value);
    }
    expect(const CaseSupplement(fee: ' ').normalized.fee, isNull);
    for (final amount in [
      '-1',
      '+1',
      '01',
      '.1',
      '1.',
      '1.001',
      '1e3',
      '1,000',
      'NaN',
      '1000000000000',
      '１２',
    ]) {
      expect(CaseSupplement(fee: amount).error, isNotNull);
    }
    for (final status in feeStatuses.keys) {
      expect(CaseSupplement(feeStatus: status).error, isNull);
    }
    expect(const CaseSupplement(feeStatus: 'UNKNOWN').error, isNotNull);
  });
}

void textContract() {
  test('可选资料去边空白，Unicode 长度边界及多行备注保留', () {
    final value = CaseSupplement(
      judge: '𠀀' * 128,
      clerk: '虚' * 128,
      clerkPhone: 'x' * 64,
      notes: '注' * 10000,
    );
    expect(value.error, isNull);
    for (final invalid in [
      CaseSupplement(judge: '𠀀' * 129),
      CaseSupplement(clerk: '虚' * 129),
      CaseSupplement(clerkPhone: 'x' * 65),
      CaseSupplement(notes: '注' * 10001),
    ]) {
      expect(invalid.error, isNotNull);
    }
    final clean = const CaseSupplement(
      judge: ' ',
      clerk: ' 虚构书记员 ',
      clerkPhone: '\n',
      notes: ' 首行\n次行 ',
    ).normalized;
    expect(clean.judge, isNull);
    expect(clean.clerk, '虚构书记员');
    expect(clean.clerkPhone, isNull);
    expect(clean.notes, '首行\n次行');
  });
}

void wireContract() {
  test('详情拒绝损坏金额和超长资料，不回显输入', () {
    for (final patch in <Map<String, Object?>>[
      {'fee': 12.34},
      {'fee': '-1.00'},
      {'fee': '1e3'},
      {'clerkPhone': 'x' * 65},
      {'notes': '注' * 10001},
    ]) {
      expect(
        () => readCaseDetail({...detailFixture(), ...patch}),
        throwsA(
          isA<ApiFailure>().having((e) => e.message, 'safe', '服务响应格式异常。'),
        ),
      );
    }
    expect(readCaseDetail(detailFixture()).supplement.fee, '12.34');
  });
}

void repositoryContract() {
  test('真实仓库只 PATCH 六项资料，清空明确写 null，非法金额不请求', () async {
    final requests = <RequestOptions>[];
    final session = ApiSession(
      'https://example.invalid',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((request) {
          if (request.path == '/auth/login') return reply(tokens());
          requests.add(request);
          return reply({'id': 'case-1'});
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final repository = ApiRepository(session);
    await repository.saveSupplement(
      'one/two',
      const CaseSupplement(
        judge: ' 虚构审判员 ',
        clerk: '虚构书记员',
        clerkPhone: ' ',
        notes: '虚构\n备注',
        fee: '999999999999.9',
        feeStatus: 'PARTIAL',
      ),
    );
    expect(requests.single.method, 'PATCH');
    expect(requests.single.path, '/cases/one%2Ftwo');
    expect(requests.single.data, {
      'judge': '虚构审判员',
      'clerk': '虚构书记员',
      'clerkPhone': null,
      'notes': '虚构\n备注',
      'fee': '999999999999.90',
      'feeStatus': 'PARTIAL',
    });
    await repository.saveSupplement('one/two', const CaseSupplement());
    expect(requests.last.data, {
      'judge': null,
      'clerk': null,
      'clerkPhone': null,
      'notes': null,
      'fee': null,
      'feeStatus': 'UNPAID',
    });
    await expectLater(
      repository.saveSupplement('one/two', const CaseSupplement(fee: '-1')),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests.length, 2);
  });
}

void memoryContract() {
  test('离线修改更新时间、保留关联数据和其他案；失败不写、清空及已删案件拒绝', () async {
    var now = DateTime.utc(2026, 1, 1);
    final repository = MemoryExperience(now: () => now);
    final id = await repository.create(
      '(2026)虚构民初1号',
      '虚构案由',
      '虚构法院',
      parties: [const CaseParty(name: '虚构甲', role: 'PLAINTIFF')],
    );
    final other = await repository.create('(2026)虚构民初2号', '虚构案由', '虚构法院');
    await repository.addTask(id, '虚构任务');
    await repository.addSample(id);
    final before = (await repository.load()).last;
    now = DateTime.utc(2026, 1, 2);
    await repository.saveSupplement(
      id,
      const CaseSupplement(
        notes: ' 虚构备注 ',
        clerkPhone: '虚构电话',
        fee: '0',
        feeStatus: 'WAIVED',
      ),
    );
    final after = (await repository.load()).last;
    expect(after.supplement.fee, '0.00');
    expect(after.supplement.notes, '虚构备注');
    expect(after.updatedAt, now);
    expect(before.supplement.notes, isNull);
    expect(after.fields.toJson(), before.fields.toJson());
    expect(after.parties.single.id, before.parties.single.id);
    expect(after.tasks.single.id, before.tasks.single.id);
    expect(after.files.single.id, before.files.single.id);
    now = DateTime.utc(2026, 1, 3);
    await expectLater(
      repository.saveSupplement(id, const CaseSupplement(fee: '-1')),
      throwsException,
    );
    expect((await repository.load()).last, same(after));
    await repository.update(id, after.fields);
    await repository.saveParties(id, after.parties);
    expect(
      (await repository.load()).last.supplement.toJson(),
      after.supplement.toJson(),
    );
    await repository.saveSupplement(id, const CaseSupplement());
    expect((await repository.load()).last.supplement.clerkPhone, isNull);
    expect((await repository.load()).last.supplement.fee, isNull);
    expect((await repository.load()).first.id, other);
    expect((await repository.load()).first.supplement.notes, isNull);
    await repository.remove(id);
    await expectLater(
      repository.saveSupplement(id, const CaseSupplement()),
      throwsException,
    );
  });
}
