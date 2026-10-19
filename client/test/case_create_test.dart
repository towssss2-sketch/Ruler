import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/case_detail.dart';
import 'package:ruler_client/domain/experience.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'api_fixture.dart';

const newParties = [
  CaseParty(name: '虚构甲', role: 'DEFENDANT', phone: '虚构电话'),
  CaseParty(name: '虚构乙', role: 'THIRD_PARTY', address: '虚构地址'),
];
void main() {
  apiContract();
  memoryContract();
}

void apiContract() {
  test('多人建案只提交一次 POST，拒绝空名单、非法角色和旧身份，不留下补写请求', () async {
    final requests = <RequestOptions>[];
    final session = ApiSession(
      'https://example.invalid',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((request) {
          if (request.path == '/auth/login') return reply(tokens());
          requests.add(request);
          return reply({
            'id': 'created',
            'stage': 'FIRST_INSTANCE',
            'status': 'ACTIVE',
            ...request.data as Map<String, Object?>,
          }, 201);
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final repository = ApiRepository(session);
    final created = await repository.createCaseWithParties(
      '(2026)虚构民初1号',
      '虚构',
      '虚构',
      newParties,
    );
    expect(created.id, 'created');
    expect(requests.single.method, 'POST');
    expect(requests.single.path, '/cases');
    expect(
      (requests.single.data as Map)['parties'],
      newParties.map((p) => p.toJson()).toList(),
    );
    for (final invalid in <List<CaseParty>>[
      [],
      [newParties.first.identified('foreign')],
      [const CaseParty(name: '虚构', role: 'UNKNOWN')],
      List.filled(101, newParties.first),
    ]) {
      await expectLater(
        repository.createCaseWithParties('虚构', '虚构', '虚构', invalid),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(requests.length, 1);
  });
}

void memoryContract() {
  test('离线多人原子创建：失败无案件，成功分配独立身份，重复建案不覆盖名单', () async {
    final repository = MemoryExperience();
    for (final invalid in <List<CaseParty>>[
      [],
      [newParties.first.identified('foreign')],
    ]) {
      await expectLater(
        repository.create('虚构', '虚构', '虚构', parties: invalid),
        throwsA(isA<ExperienceFailure>()),
      );
      expect(await repository.load(), isEmpty);
    }
    final id = await repository.create('虚构', '虚构', '虚构', parties: newParties);
    final record = (await repository.load()).single;
    expect(record.id, id);
    expect(record.parties.map((p) => p.name), ['虚构甲', '虚构乙']);
    expect(record.parties.map((p) => p.id).toSet().length, 2);
    expect(record.parties.every((p) => p.id != null), isTrue);
    expect(record.parties.first.phone, '虚构电话');
    await expectLater(
      repository.create('虚构', '虚构', '虚构', parties: [newParties.last]),
      throwsA(isA<ExperienceFailure>()),
    );
    expect((await repository.load()).single.parties, record.parties);
  });
}
