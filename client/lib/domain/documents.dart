import 'online.dart';

const maxDocumentBytes = 200 * 1024 * 1024;
const documentCategories = {
  'PLEADING': '起诉材料',
  'DEFENSE': '答辩材料',
  'EVIDENCE': '证据材料',
  'SUMMONS': '开庭传票',
  'AUTHORIZATION': '授权材料',
  'HEARING_RECORD': '庭审笔录',
  'REPRESENTATION': '代理意见',
  'JUDGMENT': '判决书',
  'COURT_DOCUMENT': '法院文件',
  'SERVICE_CONTRACT': '服务合同',
  'OTHER': '其他',
};

/// 案件文件元数据；不暴露对象键或短效签名。
class CaseDocument {
  const CaseDocument({
    required this.id,
    required this.name,
    required this.category,
    required this.size,
    required this.version,
    required this.current,
  });
  final String id;
  final String name;
  final String category;
  final int size;
  final int version;
  final bool current;
}

/// 已准备的不可变文件快照；从本机分块读取，不一次装入全部内存。
class UploadSource {
  const UploadSource({
    required this.name,
    required this.mimeType,
    required this.size,
    required this.md5,
    required this.open,
  });
  final String name;
  final String mimeType;
  final int size;
  final String md5;
  final Stream<List<int>> Function() open;
}

/// 文件接口端口；页面只持有业务记录，不持有访问签名。
abstract interface class DocumentRepository {
  Future<OnlinePage<CaseDocument>> list(
    String caseId, {
    int page = 1,
    String? category,
    bool history = false,
  });
  Future<void> remove(String id);
  DocumentUpload beginUpload(
    String caseId,
    UploadSource source,
    String category, {
    String? previousId,
  });
  Future<void> download(
    CaseDocument document,
    Future<void> Function(Stream<List<int>>) consume,
  );
}

/// 手动重试继续同一票据；完成登记前不能显示“上传成功”。
abstract interface class DocumentUpload {
  bool get bytesUploaded;
  Future<CaseDocument> resume({void Function(int, int)? onProgress});
  void cancel();
}
