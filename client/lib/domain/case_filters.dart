import 'case_fields.dart';

const caseSorts = {'desc': '最近更新优先', 'asc': '较早更新优先'};

/// 已应用的查询条件；空字符串表示不限，法院沿用服务端全称精确匹配。
class CaseFilters {
  const CaseFilters({
    this.court = '',
    this.stage = '',
    this.status = '',
    this.sort = 'desc',
  });
  final String court, stage, status, sort;
  int get count =>
      [court.trim(), stage, status].where((value) => value.isNotEmpty).length;
  bool get isDefault => count == 0 && sort == 'desc';
  String get summary => [
    court.trim().isEmpty ? '全部法院' : court.trim(),
    stage.isEmpty ? '全部阶段' : caseStages[stage]!,
    status.isEmpty ? '全部状态' : caseStatuses[status]!,
    caseSorts[sort]!,
  ].join(' · ');
  String? get error {
    if (court.trim().runes.length > 128) return '法院名称不能超过 128 字';
    if ((stage.isNotEmpty && !caseStages.containsKey(stage)) ||
        (status.isNotEmpty && !caseStatuses.containsKey(status)) ||
        !caseSorts.containsKey(sort)) {
      return '请选择有效的筛选与排序条件';
    }
    return null;
  }

  Map<String, Object?> toQuery() => {
    if (court.trim().isNotEmpty) 'court': court.trim(),
    if (stage.isNotEmpty) 'stage': stage,
    if (status.isNotEmpty) 'status': status,
    'sort': sort,
  };
}
