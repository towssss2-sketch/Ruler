import '../domain/online.dart';
import '../domain/task_fields.dart';
import '../domain/today.dart';
import 'api_session.dart';
import 'task_wire.dart';

const _invalid = ApiFailure('今日任务响应异常，请刷新重试。');

/// 不过滤坏记录或假装空列表；分页、日期、来源和确认信息异常则整次失败。
TodaySnapshot readToday(Object? raw, int expectedPage) {
  final value = jsonObject(raw);
  final date = value['date'];
  final rows = value['items'];
  final total = value['total'];
  if (date is! String ||
      !validWorkDate(date) ||
      value['timeZone'] != 'Asia/Shanghai' ||
      rows is! List ||
      total is! int ||
      total < 0 ||
      total > 5000 ||
      value['page'] is! int ||
      value['pageSize'] is! int ||
      value['page'] != expectedPage ||
      expectedPage < 1 ||
      value['pageSize'] != 20 ||
      rows.length != (total - (expectedPage - 1) * 20).clamp(0, 20)) {
    throw _invalid;
  }
  final items = rows.map((row) => _task(jsonObject(row), date)).toList();
  if (items.map((item) => item.id).toSet().length != items.length) {
    throw _invalid;
  }
  return TodaySnapshot(items, total, expectedPage, date);
}

TodayTask _task(Map<String, Object?> row, String today) {
  final source = row['source'];
  final description = row['description'];
  final dueDate = readWorkDate(row['dueDate']);
  if (!taskSources.containsKey(source) ||
      row['status'] != 'TODO' ||
      dueDate == null ||
      (description != null && description is! String)) {
    throw _invalid;
  }
  final title = jsonText(row, 'title');
  if (TaskFields(title: title, description: description as String?).error !=
      null) {
    throw _invalid;
  }
  String? baseDate, type;
  if (source == 'DEADLINE_RULE') {
    _confirm(row);
    type = row['deadlineType'] as String?;
    baseDate = readWorkDate(row['baseDate']);
  } else if (dueDate.compareTo(today) > 0) {
    throw _invalid;
  }
  return TodayTask(
    id: jsonText(row, 'id'),
    caseId: jsonText(row, 'caseId'),
    caseLabel: '${jsonText(row, 'caseNo')} · ${jsonText(row, 'court')}',
    title: title,
    dueDate: dueDate,
    source: source as String,
    description: description,
    deadlineType: type,
    baseDate: baseDate,
  );
}

void _confirm(Map<String, Object?> row) {
  final confirmed = row['deadlineConfirmedAt'];
  if (!deadlineTypes.containsKey(row['deadlineType']) ||
      readWorkDate(row['baseDate']) == null ||
      confirmed is! String ||
      DateTime.tryParse(confirmed)?.toUtc().toIso8601String() != confirmed ||
      jsonText(row, 'deadlineConfirmedById').trim().isEmpty) {
    throw _invalid;
  }
}
