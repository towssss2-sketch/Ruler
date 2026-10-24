import 'dart:async';
import 'package:ruler_client/domain/device_files.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/ingestion.dart';
import 'package:ruler_client/domain/ingestion_files.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/memory_ingestion.dart';
import 'device_files_fixture.dart';

class FileInboxFixture extends MemoryIngestion {
  bool failRead = false, failAfterWrite = false;
  @override
  Future<OnlinePage<IngestionItem>> list({
    int page = 1,
    bool history = false,
  }) async {
    if (failRead) throw const ApiFailure('列表暂不可用。');
    return super.list(page: page, history: history);
  }

  @override
  Future<IngestionReceipt> addFileExample() async {
    final result = await super.addFileExample();
    if (failAfterWrite) failRead = true;
    return result;
  }
}

/// 文件处理与设备窗口均为界面替身，截图不能冒充真机或实际上传。
class IngestionFilesFixture implements IngestionFiles {
  IngestionFilesFixture(this.inbox);
  final FileInboxFixture inbox;
  late final operation = IngestionUploadFixture(inbox);
  int starts = 0, downloads = 0;
  bool failDownload = false;
  @override
  IngestionUpload begin(UploadSource source) {
    starts++;
    return operation;
  }

  @override
  Future<void> download(
    String id,
    IngestionFile file,
    Future<void> Function(Stream<List<int>>) consume,
  ) async {
    downloads++;
    if (failDownload) throw const ApiFailure('下载未完成。');
    await consume(Stream.value(List.filled(file.size, 0)));
  }
}

class IngestionUploadFixture implements IngestionUpload {
  IngestionUploadFixture(this.inbox);
  final FileInboxFixture inbox;
  int tries = 0;
  bool cancelled = false, failFirst = false;
  Completer<void>? gate;
  @override
  bool get bytesUploaded => tries > 0;
  @override
  Future<IngestionFileReceipt> resume({
    void Function(int, int)? onProgress,
  }) async {
    tries++;
    onProgress?.call(3, 3);
    await gate?.future;
    if (cancelled) throw const ApiFailure('已取消。');
    if (failFirst && tries == 1) throw const ApiFailure('登记尚未确认。');
    return await inbox.addFileExample() as IngestionFileReceipt;
  }

  @override
  void cancel() {
    cancelled = true;
    if (gate != null && !gate!.isCompleted) gate!.complete();
  }
}

class IngestionDeviceFixture extends DeviceFixture {
  String? savedName;
  int savedBytes = 0;
  bool closed = false;
  @override
  Future<bool> save(DownloadSource source) async {
    savedName = source.name;
    await source.download((stream) async {
      savedBytes = (await stream.expand((bytes) => bytes).toList()).length;
    });
    return saved;
  }

  @override
  void close() {
    closed = true;
  }
}
