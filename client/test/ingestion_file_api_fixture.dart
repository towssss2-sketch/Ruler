import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:ruler_client/infrastructure/api_ingestion_files.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/storage_transfer.dart';
import 'api_fixture.dart';
import 'document_transfer_test.dart' show sample, permit;

Map<String, Object?> attachment() => {
  'id': 'file-1',
  'fileName': sample.name,
  'mimeType': sample.mimeType,
  'sizeBytes': '3',
};
Map<String, Object?> fileReceipt({bool duplicate = false}) => {
  'id': 'inbox-file',
  'status': 'PENDING_MATCH',
  'duplicate': duplicate,
  'file': attachment(),
};

/// 内存协议替身；单独的实际 Dart/MinIO 场景验证网络与字节。
class FileApiFixture {
  final requests = <RequestOptions>[];
  int puts = 0, gets = 0;
  bool failRegister = false, failUpload = false, badReceipt = false;
  Completer<void>? registerGate;
  late final session = ApiSession(
    'http://127.0.0.1:3000',
    dio: Dio()
      ..httpClientAdapter = TestAdapter((r) async {
        requests.add(r);
        if (r.path == '/auth/login') return reply(tokens());
        if (r.path.endsWith('/presign')) return reply(permit());
        if (r.path.endsWith('/download')) return reply(permit(method: 'GET'));
        await registerGate?.future;
        if (failRegister) {
          failRegister = false;
          return reply(null, 503);
        }
        return reply(
          badReceipt ? {...fileReceipt(), 'file': null} : fileReceipt(),
        );
      }),
  );
  late final transfer = StorageTransfer(
    {'https://storage.example.invalid'},
    dio: Dio()
      ..httpClientAdapter = TestAdapter((r) {
        if (r.headers.containsKey('Authorization') ||
            r.headers.containsKey('Cookie') ||
            r.followRedirects) {
          throw StateError('对象传输边界被破坏');
        }
        if (r.method == 'GET') {
          gets++;
          return ResponseBody(
            Stream.value(Uint8List.fromList([97, 98, 99])),
            200,
            headers: {
              'content-length': ['3'],
            },
          );
        }
        puts++;
        if (failUpload) {
          failUpload = false;
          return ResponseBody.fromString('', 503);
        }
        return ResponseBody.fromString('', 200);
      }),
  );
  late final files = ApiIngestionFiles(session, transfer);
  Future<void> login() =>
      session.login('fictional@example.invalid', 'fictional-password');
  void close() {
    files.close();
    session.close();
  }
}
