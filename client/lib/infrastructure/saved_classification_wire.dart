import '../domain/documents.dart';
import '../domain/online.dart';
import '../domain/saved_classification.dart';
import 'api_session.dart';

const _invalid = ApiFailure('分类记录响应格式异常，请稍后重试。');

/// 严格区分未记录/不可用与已记录无类别；核对尝试身份、版本、原因和人工确认标记。
SavedClassification readSavedClassification(Object? data, String attemptId) {
  final row = jsonObject(data), state = row['state'];
  if (row['attemptId'] != attemptId ||
      !RegExp(
        r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
        caseSensitive: false,
      ).hasMatch(attemptId) ||
      !['RECORDED', 'NOT_RECORDED', 'NOT_AVAILABLE'].contains(state) ||
      !row.containsKey('classification')) {
    throw _invalid;
  }
  if (state != 'RECORDED') {
    if (row['classification'] != null) throw _invalid;
    return SavedClassification(attemptId: attemptId, state: state as String);
  }
  final result = jsonObject(row['classification']);
  final category = result['category'], reason = result['reason'];
  if (result['ruleVersion'] != 'title-v1' ||
      result['requiresConfirmation'] != true ||
      !result.containsKey('category') ||
      (category != null && !documentCategories.containsKey(category)) ||
      !['TITLE_MATCH', 'NO_TITLE', 'CONFLICTING_TITLES'].contains(reason) ||
      (reason == 'TITLE_MATCH') != (category != null)) {
    throw _invalid;
  }
  return SavedClassification(
    attemptId: attemptId,
    state: 'RECORDED',
    category: category as String?,
    reason: reason as String,
    ruleVersion: result['ruleVersion'] as String,
  );
}
