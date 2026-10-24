import 'documents.dart';
import 'ingestion.dart';

class IngestionFileReceipt extends IngestionReceipt {
  const IngestionFileReceipt(
    super.id,
    super.status,
    super.duplicate,
    this.file,
  );
  final IngestionFile file;
  @override
  String get message => duplicate
      ? '相同文件已接收，未重复占用容量；当前${ingestionStatuses[status]}。'
      : '文件已保存到待定区。';
}

abstract interface class IngestionFiles {
  IngestionUpload begin(UploadSource source);
  Future<void> download(
    String id,
    IngestionFile file,
    Future<void> Function(Stream<List<int>>) consume,
  );
}

abstract interface class IngestionUpload {
  bool get bytesUploaded;
  Future<IngestionFileReceipt> resume({void Function(int, int)? onProgress});
  void cancel();
}
