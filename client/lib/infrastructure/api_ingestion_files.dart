import 'package:dio/dio.dart';
import '../domain/documents.dart';
import '../domain/ingestion.dart';
import '../domain/ingestion_files.dart';
import '../domain/online.dart';
import 'api_session.dart';
import 'document_wire.dart';
import 'ingestion_file_wire.dart';
import 'storage_transfer.dart';

/// 复用私有对象传输和当前会话，只提交文件票据，不声明案件、分类或指纹。
class ApiIngestionFiles implements IngestionFiles {
  ApiIngestionFiles(this.session, this.transfer) {
    session.onClose(transfer.close);
  }
  final ApiSession session;
  final StorageTransfer transfer;
  @override
  IngestionUpload begin(UploadSource source) {
    validateFileMetadata(source.name, source.mimeType, source.size);
    if (!RegExp(r'^[A-Za-z0-9+/]{22}==$').hasMatch(source.md5)) {
      throw const ApiFailure('文件校验信息异常，请重新选择。');
    }
    return _Upload(this, source);
  }

  @override
  Future<void> download(
    String id,
    IngestionFile file,
    Future<void> Function(Stream<List<int>>) consume,
  ) async {
    final permit = TransferPermit(
      await session.request(
        'GET',
        '/ingestion/${Uri.encodeComponent(id)}/file/download',
      ),
      'GET',
    );
    await transfer.download(permit, file.size, consume);
  }

  void close() {
    session.removeCloseListener(transfer.close);
    transfer.close();
  }
}

class _Upload implements IngestionUpload {
  _Upload(this.repository, this.source);
  final ApiIngestionFiles repository;
  final UploadSource source;
  final _cancel = CancelToken();
  String? _ticket;
  TransferPermit? _permit;
  IngestionFileReceipt? _completed;
  bool _uploaded = false, _busy = false;
  @override
  bool get bytesUploaded => _uploaded;
  @override
  void cancel() => _cancel.cancel();

  @override
  Future<IngestionFileReceipt> resume({
    void Function(int, int)? onProgress,
  }) async {
    if (!repository.session.authenticated) {
      throw const ApiFailure('会话已结束，请重新登录。', sessionEnded: true);
    }
    if (_cancel.isCancelled) throw const ApiFailure('已停止上传，请刷新待定区确认结果。');
    if (_busy) throw const ApiFailure('上传正在处理，请稍候。');
    if (_completed != null) return _completed!;
    _busy = true;
    try {
      if (_ticket == null) await _prepare();
      if (!_uploaded) {
        await repository.transfer.upload(
          _permit!,
          source,
          onProgress,
          cancelToken: _cancel,
        );
        _uploaded = true;
        _permit = null;
      }
      if (_cancel.isCancelled) throw const ApiFailure('已停止上传，请刷新待定区确认结果。');
      _completed = readFileReceipt(
        await repository.session.request(
          'POST',
          '/ingestion/files',
          data: {'uploadId': _ticket},
        ),
      );
      return _completed!;
    } finally {
      _busy = false;
    }
  }

  Future<void> _prepare() async {
    final offer = jsonObject(
      await repository.session.request(
        'POST',
        '/ingestion/files/presign',
        data: {
          'fileName': source.name,
          'mimeType': source.mimeType,
          'sizeBytes': source.size,
          'contentMd5': source.md5,
        },
      ),
    );
    final permit = TransferPermit(offer, 'PUT');
    _ticket = jsonText(offer, 'uploadId');
    _permit = permit;
  }
}
