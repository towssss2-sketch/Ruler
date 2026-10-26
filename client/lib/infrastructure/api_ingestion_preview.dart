import '../domain/documents.dart';
import '../domain/ingestion_preview.dart';
import '../domain/online.dart';
import 'api_session.dart';

const _invalidPreview = ApiFailure('正文预览响应格式异常，请稍后重试。');

class ApiIngestionPreview implements IngestionPreview {
  ApiIngestionPreview(this.session);
  final ApiSession session;
  @override
  Future<IngestionPreviewResult> preview(String id) async {
    final row = jsonObject(
      await session.request(
        'POST',
        '/ingestion/${Uri.encodeComponent(id)}/preview',
        data: {},
        receiveTimeout: const Duration(seconds: 40),
      ),
    );
    final attempt = jsonText(row, 'attemptId');
    if (!RegExp(
      r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
      caseSensitive: false,
    ).hasMatch(attempt)) {
      throw _invalidPreview;
    }
    final result = jsonObject(row['extraction']);
    if (result['state'] == 'TEXT') {
      final text = jsonText(result, 'text');
      if (text.trim().isEmpty ||
          text.length > 100000 ||
          result.containsKey('reason') ||
          result.containsKey('retryable')) {
        throw _invalidPreview;
      }
      return IngestionPreviewResult(
        attemptId: attempt,
        text: text,
        suggestion: _suggestion(jsonObject(row['suggestion'])),
      );
    }
    final reason = result['reason'];
    if (result['state'] != 'MANUAL_REQUIRED' ||
        !previewReasons.containsKey(reason) ||
        result['retryable'] is! bool ||
        result.containsKey('text') ||
        !row.containsKey('suggestion') ||
        row['suggestion'] != null ||
        result['retryable'] != ['TIMEOUT', 'UNAVAILABLE'].contains(reason)) {
      throw _invalidPreview;
    }
    return IngestionPreviewResult(
      attemptId: attempt,
      reason: reason as String,
      retryable: result['retryable'] as bool,
    );
  }
}

PreviewSuggestion _suggestion(Map<String, Object?> row) {
  final category = row['category'],
      reason = row['reason'],
      numbers = row['caseNumbers'];
  if (row['ruleVersion'] != 'title-v1' ||
      row['requiresConfirmation'] != true ||
      !row.containsKey('category') ||
      (category != null && !documentCategories.containsKey(category)) ||
      !['TITLE_MATCH', 'NO_TITLE', 'CONFLICTING_TITLES'].contains(reason) ||
      (reason == 'TITLE_MATCH') != (category != null) ||
      row['caseNumbersTruncated'] is! bool ||
      numbers is! List ||
      numbers.length > 10) {
    throw _invalidPreview;
  }
  final valid = RegExp(
    r'^\([12]\d{3}\)[\p{Script=Han}\d]{1,60}号$',
    unicode: true,
  );
  if (numbers.any((value) => value is! String || !valid.hasMatch(value)) ||
      numbers.toSet().length != numbers.length ||
      (row['caseNumbersTruncated'] == true && numbers.length != 10)) {
    throw _invalidPreview;
  }
  return PreviewSuggestion(
    category: category as String?,
    reason: reason as String,
    caseNumbers: numbers.cast<String>(),
    truncated: row['caseNumbersTruncated'] as bool,
  );
}
