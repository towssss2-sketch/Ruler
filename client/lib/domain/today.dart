import 'online.dart';

const taskSources = {
  'MANUAL': '手动任务',
  'AI_GENERATED': 'AI 建议任务',
  'DEADLINE_RULE': '法定期间 · 已确认记录',
};
const deadlineTypes = {
  'APPEAL_PERIOD': '上诉期',
  'EVIDENCE_PERIOD': '举证期',
  'PRESERVATION_RENEWAL': '保全续封',
  'ENFORCEMENT_APPLICATION': '申请执行期',
  'OTHER': '其他期间',
};

/// 今日汇总独立模型；期间记录不能进入普通任务编辑器。
class TodayTask {
  const TodayTask({
    required this.id,
    required this.caseId,
    required this.title,
    required this.dueDate,
    required this.source,
    this.description,
    this.caseLabel,
    this.deadlineType,
    this.baseDate,
  });
  final String id, caseId, title, dueDate, source;
  final String? description, caseLabel, deadlineType, baseDate;
  bool get isDeadline => source == 'DEADLINE_RULE';
  int remaining(String today) => DateTime.parse(
    '${dueDate}T00:00:00Z',
  ).difference(DateTime.parse('${today}T00:00:00Z')).inDays;
  String timing(String today) {
    final days = remaining(today);
    return days < 0
        ? '逾期 ${-days} 天'
        : days == 0
        ? '今日到期'
        : '剩余 $days 天';
  }
}

class TodaySnapshot extends OnlinePage<TodayTask> {
  TodaySnapshot(super.items, super.total, super.page, this.date);
  final String date;
}

/// 离线体验使用北京时间日历日，不受设备本地时区影响。
String shanghaiDate(DateTime now) => now
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);
