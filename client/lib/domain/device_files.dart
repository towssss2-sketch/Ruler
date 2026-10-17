import 'documents.dart';

/// 设备选择返回的快照由调用方释放，原文件不受影响。
abstract interface class PreparedUpload {
  UploadSource get source;
  Future<void> dispose();
}

/// 系统文件操作端口；测试可注入替身，不把替身当真实设备。
abstract interface class DeviceFiles {
  Future<PreparedUpload?> pick();
  Future<bool> save(CaseDocument document, DocumentRepository repository);
  void close();
}
