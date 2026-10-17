import 'package:dio/dio.dart';
import '../domain/documents.dart';
import '../domain/online.dart';
import 'api_session.dart';
import 'document_wire.dart';
import 'storage_transfer.dart';

/// 文件接口与对象直传分离，登记成功才返回正式文件记录。
class ApiDocuments implements DocumentRepository {
  ApiDocuments(this.session, this.transfer) {
    session.onClose(transfer.close);
  }
  final ApiSession session;
  final StorageTransfer transfer;

  @override
  Future<OnlinePage<CaseDocument>> list(
    String caseId, {
    int page = 1,
    String? category,
    bool history = false,
  }) async => parseDocumentPage(
    await session.request(
      'GET',
      '${_casePath(caseId)}/documents',
      query: {
        'page': page,
        'pageSize': 20,
        'includeHistory': '$history',
        'category': ?category,
      },
    ),
  );

  @override
  Future<void> remove(String id) async {
    await session.request('DELETE', '/documents/${Uri.encodeComponent(id)}');
  }

  @override
  DocumentUpload beginUpload(
    String caseId,
    UploadSource source,
    String category, {
    String? previousId,
  }) {
    validateUpload(source, category);
    return _Upload(this, caseId, source, category, previousId);
  }

  @override
  Future<void> download(
    CaseDocument document,
    Future<void> Function(Stream<List<int>>) consume,
  ) async {
    final permit = TransferPermit(
      await session.request(
        'GET',
        '/documents/${Uri.encodeComponent(document.id)}/download',
      ),
      'GET',
    );
    await transfer.download(permit, document.size, consume);
  }

  /// 释放文件连接并解除会话监听，避免页面重复进入累积引用。
  void close() {
    session.removeCloseListener(transfer.close);
    transfer.close();
  }
}

class _Upload implements DocumentUpload {
  _Upload(
    this.repository,
    this.caseId,
    this.source,
    this.category,
    this.previousId,
  );
  final ApiDocuments repository;
  final String caseId;
  final UploadSource source;
  final String category;
  final String? previousId;
  String? _ticket;
  TransferPermit? _permit;
  bool _uploaded = false;
  bool _busy = false;
  CaseDocument? _completed;
  final _cancel = CancelToken();
  @override
  bool get bytesUploaded => _uploaded;

  @override
  void cancel() => _cancel.cancel();

  @override
  Future<CaseDocument> resume({void Function(int, int)? onProgress}) async {
    if (!repository.session.authenticated) {
      throw const ApiFailure('会话已结束，请重新登录。', sessionEnded: true);
    }
    if (_busy) throw const ApiFailure('上传正在处理，请稍候。');
    if (_cancel.isCancelled) throw const ApiFailure('上传已取消，请刷新文件列表确认结果。');
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
        _permit = null; // 不再保留上传签名；登记失败仅重试原票据。
      }
      if (_cancel.isCancelled) throw const ApiFailure('上传已取消，请刷新文件列表确认结果。');
      _completed = parseDocument(
        await repository.session.request(
          'POST',
          '${_casePath(caseId)}/documents',
          data: {'uploadId': _ticket, 'category': category},
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
        '${_casePath(caseId)}/documents/presign',
        data: {
          'fileName': source.name,
          'mimeType': source.mimeType,
          'sizeBytes': source.size,
          'contentMd5': source.md5,
          if (previousId != null) 'previousDocumentId': previousId,
        },
      ),
    );
    final permit = TransferPermit(offer, 'PUT');
    _ticket = jsonText(offer, 'uploadId');
    _permit = permit;
  }
}

String _casePath(String id) => '/cases/${Uri.encodeComponent(id)}';
