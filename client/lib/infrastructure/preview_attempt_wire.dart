import '../domain/ingestion_preview.dart';
import '../domain/preview_attempts.dart';
import '../domain/online.dart';
import 'api_session.dart' show jsonObject;

const _invalid = ApiFailure('提取记录响应异常，请重新加载。');

/// 严格检查分页和状态组合；不将错误响应误报为没有历史。
OnlinePage<PreviewAttempt> readPreviewAttempts(Object? value, int page) {
  final row = jsonObject(value), items = row['items'], total = row['total'];
  if (row['page'] != page ||
      row['pageSize'] != 20 ||
      total is! int ||
      total < 0 ||
      items is! List ||
      items.length != (total - (page - 1) * 20).clamp(0, 20)) {
    throw _invalid;
  }
  final parsed = items.map((item) => _attempt(jsonObject(item))).toList();
  if (parsed.map((item) => item.id).toSet().length != parsed.length) {
    throw _invalid;
  }
  return OnlinePage(List.unmodifiable(parsed), total, page);
}

PreviewAttempt _attempt(Map<String, Object?> row) {
  final id = row['id'], status = row['status'], reason = row['reason'];
  final started = _date(row['startedAt']);
  final finished = row['finishedAt'] == null ? null : _date(row['finishedAt']);
  if (id is! String ||
      !RegExp(
        r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
        caseSensitive: false,
      ).hasMatch(id) ||
      !previewAttemptStatuses.containsKey(status) ||
      !row.containsKey('reason') ||
      !row.containsKey('finishedAt') ||
      (status == 'MANUAL_REQUIRED'
          ? !previewReasons.containsKey(reason)
          : reason != null) ||
      (status == 'RUNNING') != (finished == null) ||
      (finished != null && finished.isBefore(started)) ||
      row['retryable'] !=
          (status == 'INTERRUPTED' ||
              (status == 'MANUAL_REQUIRED' &&
                  ['TIMEOUT', 'UNAVAILABLE'].contains(reason)))) {
    throw _invalid;
  }
  return PreviewAttempt(
    id: id,
    status: status as String,
    reason: reason as String?,
    startedAt: started,
    finishedAt: finished,
    retryable: row['retryable'] as bool,
  );
}

DateTime _date(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
      ).hasMatch(value)) {
    throw _invalid;
  }
  final date = DateTime.tryParse(value);
  if (date == null || date.toUtc().toIso8601String() != value) throw _invalid;
  return date;
}
