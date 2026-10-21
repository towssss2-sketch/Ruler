import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/case_detail.dart';
import 'package:ruler_client/domain/case_fields.dart';
import 'package:ruler_client/domain/case_filters.dart';
import 'package:ruler_client/domain/experience.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/experience_query.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'api_fixture.dart';

void main() {
  validation();
  apiContract();
  offlineQuery();
  updateOrder();
}

void validation() {
  test('筛选空值省略、法院去首尾空白，非法枚举和超长名称拒绝', () {
    expect(const CaseFilters().toQuery(), {'sort': 'desc'});
    const valid = CaseFilters(
      court: ' 虚构法院 ',
      stage: 'RETRIAL',
      status: 'CLOSED',
      sort: 'asc',
    );
    expect(valid.toQuery(), {
      'court': '虚构法院',
      'stage': 'RETRIAL',
      'status': 'CLOSED',
      'sort': 'asc',
    });
    expect(valid.count, 3);
    expect(valid.summary, '虚构法院 · 再审 · 已结案 · 较早更新优先');
    expect(const CaseFilters(sort: 'asc').isDefault, isFalse);
    expect(CaseFilters(court: '𠀀' * 128).error, isNull);
    for (final invalid in [
      const CaseFilters(stage: 'UNKNOWN'),
      const CaseFilters(status: 'UNKNOWN'),
      const CaseFilters(sort: 'DROP'),
      CaseFilters(court: '𠀀' * 129),
    ]) {
      expect(invalid.error, isNotNull);
    }
  });
}

void apiContract() {
  test('关键词、筛选、排序与分页一起发给服务端，取消筛选不遗留条件，非法值不请求', () async {
    final requests = <RequestOptions>[];
    final session = ApiSession(
      'https://example.invalid',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((request) {
          if (request.path == '/auth/login') return reply(tokens());
          requests.add(request);
          return reply({
            'items': [],
            'total': 0,
            'page': request.queryParameters['page'],
          });
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final repository = ApiRepository(session);
    await repository.cases(
      keyword: ' 虚构姓名 ',
      page: 2,
      filters: const CaseFilters(
        court: ' 虚构法院 ',
        stage: 'SECOND_INSTANCE',
        status: 'CLOSED',
        sort: 'asc',
      ),
    );
    expect(requests.single.method, 'GET');
    expect(requests.single.path, '/cases');
    expect(requests.single.queryParameters, {
      'keyword': '虚构姓名',
      'page': 2,
      'pageSize': 20,
      'court': '虚构法院',
      'stage': 'SECOND_INSTANCE',
      'status': 'CLOSED',
      'sort': 'asc',
    });
    await repository.cases();
    expect(requests.last.queryParameters, {
      'page': 1,
      'pageSize': 20,
      'sort': 'desc',
    });
    await expectLater(
      repository.cases(filters: const CaseFilters(sort: 'invalid')),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests.length, 2);
  });
}

ExperienceCase record(
  String id, {
  String court = '虚构法院甲',
  String stage = 'FIRST_INSTANCE',
  String status = 'ACTIVE',
  int updated = 1,
  String name = '虚构甲',
}) => ExperienceCase(
  id: id,
  caseNo: '(2026)虚构民初$id号',
  cause: '虚构合同',
  court: court,
  stage: stage,
  status: status,
  updatedAt: DateTime.utc(2026, 1, updated),
  parties: [CaseParty(name: name, role: 'PLAINTIFF')],
);
void offlineQuery() {
  test('离线组合条件采用交集、法院精确、姓名和案号搜索；时间与身份稳定排序且不改原快照', () {
    final records = [
      record('1', updated: 3),
      record('2', stage: 'SECOND_INSTANCE', status: 'CLOSED', name: '虚构乙'),
      record('3', court: '虚构法院乙', updated: 3),
    ];
    expect(queryExperienceCases(records).map((c) => c.id), ['3', '1', '2']);
    expect(
      queryExperienceCases(
        records,
        filters: const CaseFilters(sort: 'asc'),
      ).map((c) => c.id),
      ['2', '1', '3'],
    );
    expect(
      queryExperienceCases(
        records,
        keyword: '虚构乙',
        filters: const CaseFilters(
          court: ' 虚构法院甲 ',
          stage: 'SECOND_INSTANCE',
          status: 'CLOSED',
        ),
      ).single.id,
      '2',
    );
    expect(
      queryExperienceCases(records, filters: const CaseFilters(court: '虚构法院')),
      isEmpty,
    );
    expect(
      queryExperienceCases(records, keyword: '（2026）虚构民初1号').single.id,
      '1',
    );
    expect(queryExperienceCases(records, keyword: '虚构法院甲'), isEmpty);
    expect(records.map((c) => c.id), ['1', '2', '3']);
    expect(() => queryExperienceCases(records).clear(), throwsUnsupportedError);
  });
}

void updateOrder() {
  test('离线案件和名单编辑更新排序时间，失败不更新，任务与文件保留案件更新时间', () async {
    var now = DateTime.utc(2026, 1, 1);
    final repository = MemoryExperience(now: () => now);
    final first = await repository.create('(2026)虚构民初1号', '虚构', '虚构');
    now = DateTime.utc(2026, 1, 2);
    final second = await repository.create('(2026)虚构民初2号', '虚构', '虚构');
    expect(queryExperienceCases(await repository.load()).first.id, second);
    now = DateTime.utc(2026, 1, 3);
    await repository.update(
      first,
      const CaseFields(caseNo: '(2026)虚构民初1号', cause: '虚构修改', court: '虚构'),
    );
    expect(queryExperienceCases(await repository.load()).first.id, first);
    now = DateTime.utc(2026, 1, 4);
    await expectLater(
      repository.update(
        first,
        const CaseFields(caseNo: 'bad', cause: '虚构', court: '虚构'),
      ),
      throwsA(isA<ExperienceFailure>()),
    );
    await repository.addTask(first, '虚构任务');
    await repository.addSample(first);
    expect(
      (await repository.load()).singleWhere((c) => c.id == first).updatedAt,
      DateTime.utc(2026, 1, 3),
    );
    await repository.saveParties(second, [
      const CaseParty(name: '虚构乙', role: 'DEFENDANT'),
    ]);
    expect(queryExperienceCases(await repository.load()).first.id, second);
    await repository.remove(second);
    expect(queryExperienceCases(await repository.load()).single.id, first);
  });
}
