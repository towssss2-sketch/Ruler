import '../domain/ingestion.dart';
import '../domain/online.dart';
import 'api_session.dart';
import 'ingestion_file_wire.dart';

const _invalid = ApiFailure('材料响应异常，请刷新重试。');

/// 状态未知、正文损坏均整体拒绝，不能把错误显示为成功或空清单。
IngestionItem readIngestionItem(Object? raw, {bool detail = false}) {
  final row = jsonObject(raw);
  final preview = row['preview'];
  final date = row['receivedAt'];
  final time = date is String ? DateTime.tryParse(date) : null;
  final text = row['rawContent'];
  if (!ingestionStatuses.containsKey(row['status']) ||
      !ingestionChannels.containsKey(row['channel']) ||
      preview is! String ||
      preview.trim().isEmpty ||
      preview.runes.length > 200 ||
      time == null ||
      time.toUtc().toIso8601String() != date ||
      (detail && (text is! String || ingestionTextError(text) != null))) {
    throw _invalid;
  }
  return IngestionItem(
    id: jsonText(row, 'id'),
    channel: row['channel'] as String,
    status: row['status'] as String,
    preview: preview,
    receivedAt: time,
    rawContent: detail ? text as String : null,
    file: row['file'] == null ? null : readIngestionFile(row['file']),
  );
}

OnlinePage<IngestionItem> readIngestionPage(
  Object? raw,
  int page,
  bool history,
) {
  final row = jsonObject(raw);
  final items = row['items'];
  final total = row['total'];
  if (items is! List ||
      total is! int ||
      total < 0 ||
      row['page'] is! int ||
      row['page'] != page ||
      page < 1 ||
      row['pageSize'] is! int ||
      row['pageSize'] != 20 ||
      items.length != (total - (page - 1) * 20).clamp(0, 20)) {
    throw _invalid;
  }
  final parsed = items.map((item) => readIngestionItem(item)).toList();
  if (parsed.map((item) => item.id).toSet().length != parsed.length ||
      (!history && parsed.any((item) => item.status != 'PENDING_MATCH'))) {
    throw _invalid;
  }
  return OnlinePage(parsed, total, page);
}

IngestionReceipt readIngestionReceipt(Object? raw) {
  final row = jsonObject(raw);
  if (!ingestionStatuses.containsKey(row['status']) ||
      row['duplicate'] is! bool ||
      (row['duplicate'] == false && row['status'] != 'PENDING_MATCH')) {
    throw _invalid;
  }
  return IngestionReceipt(
    jsonText(row, 'id'),
    row['status'] as String,
    row['duplicate'] as bool,
  );
}
