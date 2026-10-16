import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

/// 内存 HTTP 适配器，仅用于协议故障和并发控制测试。
class TestAdapter implements HttpClientAdapter {
  TestAdapter(this.handle);
  final FutureOr<ResponseBody> Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handle(options);
  @override
  void close({bool force = false}) {}
}

/// 构造真实标准信封形状，不代表实际服务器已执行。
ResponseBody reply(Object? data, [int status = 200]) => ResponseBody.fromString(
  jsonEncode({
    'code': status < 300 ? 0 : status,
    'data': data,
    'message': 'unsafe-server-payload',
    'traceId': 'fixture',
  }),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// 测试用非真实令牌，禁止用于实际环境。
Map<String, Object?> tokens([String suffix = 'one']) => {
  'accessToken': 'fictional-access-$suffix',
  'refreshToken': 'fictional-refresh-$suffix',
  'tokenType': 'Bearer',
};
