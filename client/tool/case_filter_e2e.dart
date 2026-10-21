import 'package:ruler_client/domain/case_filters.dart';
import 'package:ruler_client/domain/case_fields.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'connected_e2e.dart' show check;

/// 复用本轮自有历史夹具，实际检验交集、全称匹配与数据库更新时间排序。
Future<void> filterScenario(ApiRepository repository, List<String> ids) async {
  const court = '虚构历史法院';
  final newest = await repository.cases(
    filters: const CaseFilters(court: court),
  );
  check(newest.total == 2 && newest.items.first.id == ids.last);
  final oldest = await repository.cases(
    filters: const CaseFilters(court: court, sort: 'asc'),
  );
  check(oldest.total == 2 && oldest.items.first.id == ids.first);
  await repository.updateCase(
    ids.first,
    const CaseFields(
      caseNo: '(2026)虚构民初101号',
      cause: '虚构历史案由',
      court: court,
      stage: 'ENFORCEMENT',
      status: 'CLOSED',
    ),
  );
  final updated = await repository.cases(
    filters: const CaseFilters(court: court),
  );
  check(updated.items.first.id == ids.first);
  const combined = CaseFilters(
    court: court,
    stage: 'ENFORCEMENT',
    status: 'CLOSED',
    sort: 'asc',
  );
  final selected = await repository.cases(
    keyword: '虚构紫杉专用甲',
    filters: combined,
  );
  check(selected.total == 1 && selected.items.single.id == ids.first);
  final remaining = await repository.cases(
    filters: const CaseFilters(
      court: court,
      stage: 'FIRST_INSTANCE',
      status: 'ACTIVE',
    ),
  );
  check(remaining.total == 1 && remaining.items.single.id == ids.last);
  check(
    (await repository.cases(filters: const CaseFilters(court: '虚构历史'))).total ==
        0,
  );
  final emptyPage = await repository.cases(
    page: 2,
    keyword: '虚构紫杉专用甲',
    filters: combined,
  );
  check(emptyPage.items.isEmpty && emptyPage.total == 1 && emptyPage.page == 2);
}
