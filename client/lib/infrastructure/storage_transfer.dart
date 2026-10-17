import 'package:dio/dio.dart';
import '../domain/documents.dart';
import '../domain/online.dart';
import 'api_session.dart';

/// 短效签名仅在内存使用，禁止日志、页面或磁盘记录。
class TransferPermit {
  TransferPermit(Object? input, this.method) {
    final data = jsonObject(input);
    url = jsonText(data, 'url');
    final rawHeaders = jsonObject(data['headers']);
    if (data['method'] != method ||
        rawHeaders.values.any((v) => v is! String)) {
      throw const ApiFailure('文件传输凭证异常。');
    }
    headers = Map.unmodifiable(rawHeaders.cast<String, String>());
    final date = DateTime.tryParse(jsonText(data, 'expiresAt'));
    if (date == null) throw const ApiFailure('文件传输凭证异常。');
    expiresAt = date;
  }
  late final String url;
  final String method;
  late final Map<String, String> headers;
  late final DateTime expiresAt;
}

/// 独立的无登录凭据连接；只访问构建配置允许的源，不追随重定向。
class StorageTransfer {
  StorageTransfer(Set<String> origins, {Dio? dio})
    : _origins = origins.map(validateApiOrigin).toSet(),
      _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false,
      validateStatus: (status) => status != null && status < 600,
    );
  }
  final Set<String> _origins;
  final Dio _dio;
  final CancelToken _cancel = CancelToken();
  final Set<CancelToken> _downloads = {};
  bool _closed = false;

  /// PUT 绑定原尺寸、MIME 和 MD5；不做隐式重试，不发送 JWT 或 Cookie。
  Future<void> upload(
    TransferPermit permit,
    UploadSource source,
    void Function(int, int)? progress,
  ) async {
    _validate(permit);
    final expected = {
      'content-type': source.mimeType,
      'content-length': '${source.size}',
      'content-md5': source.md5,
    };
    if (permit.method != 'PUT' ||
        permit.headers.length != expected.length ||
        expected.entries.any((e) => permit.headers[e.key] != e.value)) {
      throw const ApiFailure('上传凭证与所选文件不符。');
    }
    try {
      final response = await _dio.put<Object?>(
        permit.url,
        data: _bounded(source.open(), source.size),
        cancelToken: _cancel,
        options: Options(
          headers: permit.headers,
          responseType: ResponseType.plain,
        ),
        onSendProgress: progress,
      );
      _success(response.statusCode);
    } catch (_) {
      throw const ApiFailure('文件传输未完成，请重试本次上传。');
    }
  }

  /// 流式下载，核对精确长度；完整成功后由调用方保存到用户位置。
  Future<void> download(
    TransferPermit permit,
    int size,
    Future<void> Function(Stream<List<int>>) consume,
  ) async {
    _validate(permit);
    if (permit.method != 'GET' ||
        permit.headers.isNotEmpty ||
        size < 1 ||
        size > maxDocumentBytes) {
      throw const ApiFailure('下载凭证异常。');
    }
    final cancel = CancelToken();
    _downloads.add(cancel);
    var complete = false;
    try {
      final response = await _dio.get<ResponseBody>(
        permit.url,
        cancelToken: cancel,
        options: Options(responseType: ResponseType.stream),
      );
      _success(response.statusCode);
      await consume(
        _bounded(
          response.data!.stream,
          size,
          onComplete: () => complete = true,
        ),
      );
      if (_closed || !complete) throw const ApiFailure('文件传输未完成。');
    } catch (_) {
      throw const ApiFailure('下载未完成，未保存文件，请重试。');
    } finally {
      _downloads.remove(cancel);
      cancel.cancel(); // 错误状态或接收方提前退出也释放响应流。
    }
  }

  /// 会话关闭或页面销毁时取消传输，不继续使用尚有效的签名。
  void close() {
    _closed = true;
    _cancel.cancel();
    for (final cancel in _downloads) {
      cancel.cancel();
    }
    _dio.close(force: true);
  }

  void _validate(TransferPermit permit) {
    final uri = Uri.tryParse(permit.url);
    if (_closed) throw const ApiFailure('文件传输已取消。');
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        !uri.hasAuthority ||
        !_origins.contains(uri.origin) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const ApiFailure('文件服务尚未配置或地址不受信任。');
    }
    final remaining = permit.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero || remaining > const Duration(minutes: 10)) {
      throw const ApiFailure('文件传输凭证已过期或无效，请重新选择文件。');
    }
  }

  void _success(int? status) {
    if (_closed || status == null || status < 200 || status >= 300) {
      throw const ApiFailure('文件传输未完成。');
    }
  }

  Stream<List<int>> _bounded(
    Stream<List<int>> source,
    int expected, {
    void Function()? onComplete,
  }) async* {
    var count = 0;
    await for (final chunk in source) {
      count += chunk.length;
      if (_closed || count > expected) throw const ApiFailure('文件长度不符或传输已取消。');
      yield chunk;
    }
    if (count != expected) throw const ApiFailure('文件长度不符。');
    onComplete?.call();
  }
}
