import '../domain/documents.dart';
import '../domain/online.dart';
import 'api_session.dart';

const mimeExtensions = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'mp4': 'video/mp4',
};

/// 申请票据前验证长度、扩展名与协议摘要；MD5 不是安全扫描。
void validateUpload(UploadSource source, String category) {
  if (source.size < 1 ||
      source.size > maxDocumentBytes ||
      source.name.isEmpty ||
      source.name.length > 512 ||
      !source.name.contains('.') ||
      RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(source.name) ||
      mimeExtensions[source.name.split('.').last.toLowerCase()] !=
          source.mimeType ||
      !RegExp(r'^[A-Za-z0-9+/]{22}==$').hasMatch(source.md5) ||
      !documentCategories.containsKey(category)) {
    throw const ApiFailure('请选择不超过 200 MiB 的非空 PDF、Word、图片或 MP4 文件，并选择分类。');
  }
}

/// 严格解析文件元数据，拒绝损坏的尺寸或不明分类。
CaseDocument parseDocument(Object? input) {
  final data = jsonObject(input);
  final size = data['sizeBytes'];
  final bytes = size is String ? int.tryParse(size) : null;
  final version = data['version'];
  final current = data['isCurrentVersion'];
  final category = jsonText(data, 'category');
  if (bytes == null ||
      bytes < 1 ||
      bytes > maxDocumentBytes ||
      version is! int ||
      version < 1 ||
      current is! bool ||
      !documentCategories.containsKey(category)) {
    throw const ApiFailure('文件记录格式异常。');
  }
  return CaseDocument(
    id: jsonText(data, 'id'),
    name: jsonText(data, 'fileName'),
    category: category,
    size: bytes,
    version: version,
    current: current,
  );
}

/// 保留真实服务端分页信息，不默默截断历史版本。
OnlinePage<CaseDocument> parseDocumentPage(Object? input) {
  final data = jsonObject(input);
  final items = data['items'];
  final total = data['total'];
  final page = data['page'];
  if (items is! List ||
      total is! int ||
      total < 0 ||
      page is! int ||
      page < 1) {
    throw const ApiFailure('文件列表格式异常。');
  }
  return OnlinePage(items.map(parseDocument).toList(), total, page);
}
