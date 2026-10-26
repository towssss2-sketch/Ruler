/// 正文只属于当前预览，不持久化；分类及案号均是待人工核对的候选。
class IngestionPreviewResult {
  const IngestionPreviewResult({
    required this.attemptId,
    this.text,
    this.suggestion,
    this.reason,
    this.retryable = false,
  });
  final String attemptId;
  final String? text, reason;
  final PreviewSuggestion? suggestion;
  final bool retryable;
}

class PreviewSuggestion {
  PreviewSuggestion({
    required this.reason,
    required List<String> caseNumbers,
    this.category,
    this.truncated = false,
  }) : caseNumbers = List.unmodifiable(caseNumbers);
  final String reason;
  final String? category;
  final List<String> caseNumbers;
  final bool truncated;
}

abstract interface class IngestionPreview {
  Future<IngestionPreviewResult> preview(String id);
}

const previewReasons = {
  'UNSUPPORTED_FORMAT': '暂不支持这种格式的正文提取。目前支持 PDF 和 DOCX，图片识别尚未接入。',
  'FILE_TOO_LARGE': '文件超过本次正文预览的 10 MiB 上限，原件仍保留。',
  'CONTENT_LIMIT': '页数、正文长度或解压内容超过处理上限，本次未返回部分正文。',
  'NO_TEXT': '没有提取到可读正文。扫描件或图片需要文字识别，当前可先人工查看原件。',
  'INVALID_DOCUMENT': '文件无法解析，可能已损坏、受密码保护或实际格式不符，请人工查看原件。',
  'UNSUPPORTED_CONTENT': '文件包含尚不支持的内容，未把部分提取作为完整结果，请人工核对。',
  'TIMEOUT': '本次提取超时，原件未改变，可以稍后重试。',
  'UNAVAILABLE': '正文提取暂不可用，原件未改变，可以稍后重试。',
};
