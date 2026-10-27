import '../domain/ingestion_preview.dart';
import '../domain/ingestion.dart';
import '../domain/online.dart';
import '../domain/preview_attempts.dart';

/// 固定虚构正文，仅用于离线点击体验，不读取设备或声称执行 PDF 解析。
class MemoryIngestionPreview implements IngestionPreview, PreviewAttempts {
  MemoryIngestionPreview(this.inbox);
  final IngestionRepository inbox;
  int _attempt = 0;
  final _history = <String, List<PreviewAttempt>>{};
  @override
  Future<OnlinePage<PreviewAttempt>> attempts(String id, {int page = 1}) async {
    if (page < 1 || page > 9999) throw const ApiFailure('页码无效。');
    if ((await inbox.detail(id)).file == null) {
      throw const ApiFailure('这份材料没有附件。');
    }
    final rows = _history[id] ?? [];
    return OnlinePage(
      List.unmodifiable(rows.skip((page - 1) * 20).take(20)),
      rows.length,
      page,
    );
  }

  @override
  Future<IngestionPreviewResult> preview(String id) async {
    final item = await inbox.detail(id);
    if (item.file == null) throw const ApiFailure('这份材料没有附件。');
    final attemptId = 'demo-preview-${++_attempt}',
        now = DateTime.now().toUtc();
    (_history[id] ??= []).insert(
      0,
      PreviewAttempt(
        id: attemptId,
        status: 'SUCCEEDED',
        startedAt: now,
        finishedAt: now,
      ),
    );
    return IngestionPreviewResult(
      attemptId: attemptId,
      text:
          '法律服务合同\n（2026）虚构民初90号\n\n'
          '本段为预置的虚构正文示例，没有读取或解析真实文件。\n'
          '虚构委托方与虚构律师约定提供法律服务。具体内容由经办人核对。',
      suggestion: PreviewSuggestion(
        category: 'SERVICE_CONTRACT',
        reason: 'TITLE_MATCH',
        caseNumbers: ['(2026)虚构民初90号'],
      ),
    );
  }
}
