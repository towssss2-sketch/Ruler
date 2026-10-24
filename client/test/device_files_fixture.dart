import 'dart:async';
import 'package:ruler_client/domain/device_files.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/online.dart';
import 'document_widget_test.dart' show FilesFixture;
import 'document_transfer_test.dart' show sample;

/// 只作界面协议替身，不调用操作系统窗口或假称真实设备。
class DeviceFixture implements DeviceFiles {
  final selected = PreparedFixture();
  bool cancelPick = false;
  bool saved = true;
  Completer<PreparedUpload?>? delayedPick;
  @override
  Future<PreparedUpload?> pick() async => delayedPick != null
      ? delayedPick!.future
      : cancelPick
      ? null
      : selected;
  @override
  Future<bool> save(DownloadSource source) async => saved;
  @override
  void close() {}
}

class PreparedFixture implements PreparedUpload {
  bool disposed = false;
  @override
  UploadSource get source => sample;
  @override
  Future<void> dispose() async => disposed = true;
}

class UploadFixture implements DocumentUpload {
  int tries = 0;
  bool cancelled = false;
  bool failFirst = false;
  Completer<CaseDocument>? delayed;
  @override
  bool get bytesUploaded => tries > 0;
  @override
  void cancel() {
    cancelled = true;
    if (delayed != null && !delayed!.isCompleted) {
      delayed!.completeError(const ApiFailure('已取消'));
    }
  }

  @override
  Future<CaseDocument> resume({void Function(int, int)? onProgress}) async {
    tries++;
    onProgress?.call(3, 3);
    if (delayed != null) return delayed!.future;
    if (failFirst && tries == 1) throw const ApiFailure('登记尚未确认。');
    return const CaseDocument(
      id: 'uploaded',
      name: '虚构.pdf',
      category: 'OTHER',
      size: 3,
      version: 1,
      current: true,
    );
  }
}

class UploadRepositoryFixture extends FilesFixture {
  final operation = UploadFixture();
  int starts = 0;
  String? previous;
  String? uploadCategory;
  @override
  DocumentUpload beginUpload(
    String caseId,
    UploadSource source,
    String category, {
    String? previousId,
  }) {
    starts++;
    previous = previousId;
    uploadCategory = category;
    return operation;
  }
}
