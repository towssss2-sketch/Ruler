import '../domain/case_fields.dart';
import '../domain/online.dart';
import 'api_session.dart';

const _badMatch = ApiFailure('案号查找响应异常，请重试；尚未选择案件。');

void validateCaseMatch(String number, int page) {
  if (validateCaseNumber(number) != null ||
      number.runes.length > 80 ||
      page < 1 ||
      page > 9999) {
    throw const ApiFailure('请使用完整案号和有效页码。');
  }
}

/// 拒绝旧后端忽略精确条件后的宽泛列表，不在当前页伪造全库匹配。
OnlinePage<OnlineCase> readCaseMatches(Object? value, String number, int page) {
  final row = jsonObject(value), total = row['total'], items = row['items'];
  if (row['group'] != 'owned' ||
      row['collaborationEnabled'] != false ||
      row['page'] != page ||
      row['pageSize'] != 20 ||
      total is! int ||
      total < 0 ||
      items is! List ||
      items.length != (total - (page - 1) * 20).clamp(0, 20)) {
    throw _badMatch;
  }
  final result = items
      .map((value) => _match(jsonObject(value), number))
      .toList();
  if (result.map((item) => item.id).toSet().length != result.length) {
    throw _badMatch;
  }
  return OnlinePage(result, total, page);
}

OnlineCase _match(Map<String, Object?> row, String number) {
  final id = jsonText(row, 'id'), caseNo = jsonText(row, 'caseNo');
  final cause = jsonText(row, 'cause'), court = jsonText(row, 'court');
  final stage = row['stage'], status = row['status'];
  if (!RegExp(
        r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
        caseSensitive: false,
      ).hasMatch(id) ||
      caseNo != number ||
      cause.trim().isEmpty ||
      cause.runes.length > 128 ||
      court.trim().isEmpty ||
      court.runes.length > 128 ||
      !caseStages.containsKey(stage) ||
      !caseStatuses.containsKey(status)) {
    throw _badMatch;
  }
  return OnlineCase(
    id,
    caseNo,
    cause,
    court,
    stage: stage as String,
    status: status as String,
  );
}
