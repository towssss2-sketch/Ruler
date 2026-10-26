import '../domain/ingestion_preview.dart';
import '../domain/ingestion.dart';
import '../domain/online.dart';

/// 固定虚构正文，仅用于离线点击体验，不读取设备或声称执行 PDF 解析。
class MemoryIngestionPreview implements IngestionPreview {
  MemoryIngestionPreview(this.inbox);
  final IngestionRepository inbox;
  int _attempt = 0;
  @override
  Future<IngestionPreviewResult> preview(String id) async {
    final item = await inbox.detail(id);
    if (item.file == null) throw const ApiFailure('这份材料没有附件。');
    return IngestionPreviewResult(
      attemptId: 'demo-preview-${++_attempt}',
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
