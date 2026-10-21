import '../domain/case_filters.dart';
import '../domain/experience.dart';

/// 仅对当前虚构内存记录筛选；与线上字段/排序语义一致，不代表数据库查询。
List<ExperienceCase> queryExperienceCases(
  List<ExperienceCase> records, {
  String keyword = '',
  CaseFilters filters = const CaseFilters(),
}) {
  if (filters.error != null) throw ExperienceFailure(filters.error!);
  final search = keyword.trim();
  final numberSearch = search.replaceAll('（', '(').replaceAll('）', ')');
  final items = records
      .where(
        (item) =>
            (filters.court.trim().isEmpty ||
                item.court == filters.court.trim()) &&
            (filters.stage.isEmpty || item.stage == filters.stage) &&
            (filters.status.isEmpty || item.status == filters.status) &&
            (search.isEmpty ||
                item.caseNo
                    .replaceAll('（', '(')
                    .replaceAll('）', ')')
                    .contains(numberSearch) ||
                item.cause.contains(search) ||
                item.parties.any((party) => party.name.contains(search))),
      )
      .toList();
  items.sort((a, b) {
    final date = a.updatedAt.compareTo(b.updatedAt);
    final order = date == 0 ? a.id.compareTo(b.id) : date;
    return filters.sort == 'asc' ? order : -order;
  });
  return List.unmodifiable(items);
}
