import '../domain/case_conflict.dart';
import '../domain/online.dart';
import 'api_session.dart';

/// 固定阈值和分页协议异常时拒绝显示，避免把坏响应误报为未命中。
OnlinePage<CaseConflict> readConflictPage(
  Object? raw, {
  required int expectedPage,
}) {
  final value = jsonObject(raw);
  final rows = value['items'];
  final total = value['total'];
  final page = value['page'];
  if (rows is! List ||
      rows.length > 20 ||
      total is! int ||
      total < 0 ||
      page is! int ||
      page < 1 ||
      page != expectedPage ||
      value['pageSize'] != 20 ||
      value['threshold'] != 0.6 ||
      total < rows.length) {
    throw const ApiFailure('服务响应格式异常。');
  }
  final items = rows.map(_match).toList();
  if (items.map((item) => item.caseId).toSet().length != items.length) {
    throw const ApiFailure('服务响应格式异常。');
  }
  return OnlinePage(items, total, page);
}

CaseConflict _match(Object? raw) {
  final value = jsonObject(raw);
  final deleted = value['deleted'];
  final score = value['similarity'];
  if (deleted is! bool ||
      score is! num ||
      !score.isFinite ||
      score < 0.6 ||
      score > 1) {
    throw const ApiFailure('服务响应格式异常。');
  }
  return CaseConflict(
    caseId: jsonText(value, 'caseId'),
    caseNo: jsonText(value, 'caseNo'),
    court: jsonText(value, 'court'),
    deleted: deleted,
    similarity: score.toDouble(),
  );
}
