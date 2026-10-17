import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_documents.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/storage_transfer.dart';
import 'api_fixture.dart';

const sample = UploadSource(
  name: '虚构.pdf',
  mimeType: 'application/pdf',
  size: 3,
  md5: 'kAFQmDzST7DWlj99KOF/cg==',
  open: sampleBytes,
);
Stream<List<int>> sampleBytes() => Stream.value([97, 98, 99]);

Map<String, Object?> permit({
  String url = 'https://storage.example.invalid/object?secret=fixture',
  String method = 'PUT',
  Map<String, String>? headers,
  DateTime? expires,
}) => {
  'url': url,
  'method': method,
  'uploadId': 'ticket-1',
  'headers':
      headers ??
      (method == 'GET'
          ? <String, String>{}
          : {
              'content-type': sample.mimeType,
              'content-md5': sample.md5,
              'content-length': '3',
            }),
  'expiresAt': (expires ?? DateTime.now().add(const Duration(minutes: 5)))
      .toIso8601String(),
};

Map<String, Object?> document() => {
  'id': 'doc-1',
  'fileName': sample.name,
  'category': 'EVIDENCE',
  'sizeBytes': '3',
  'version': 1,
  'isCurrentVersion': true,
};

void main() {
  test('存储独立连接不带 JWT、不跟随重定向并保持签名头', () async {
    var requests = 0;
    final transfer = StorageTransfer(
      {'https://storage.example.invalid'},
      dio: Dio()
        ..httpClientAdapter = TestAdapter((options) {
          requests++;
          expect(options.headers.containsKey('Authorization'), false);
          expect(options.headers.containsKey('Cookie'), false);
          expect(options.followRedirects, false);
          expect(options.headers['content-md5'], sample.md5);
          return ResponseBody.fromString('', 200);
        }),
    );
    addTearDown(transfer.close);
    await transfer.upload(TransferPermit(permit(), 'PUT'), sample, null);
    expect(requests, 1);
  });
  rejectionTests();
  retryTests();
  cancellationTest();
  downloadTests();
  downloadCleanupTests();
}

void rejectionTests() {
  final bad = [
    permit(url: 'http://storage.example.invalid/object'),
    permit(url: 'https://other.example.invalid/object'),
    permit(url: '/relative'),
    permit(url: 'file:///tmp/object'),
    permit(headers: {'Authorization': 'fixture'}),
    permit(expires: DateTime.now().subtract(const Duration(seconds: 1))),
  ];
  for (var i = 0; i < bad.length; i++) {
    test('不可信或过期传输凭据在联网前拒绝 $i', () async {
      var calls = 0;
      final transfer = StorageTransfer(
        {'https://storage.example.invalid'},
        dio: Dio()
          ..httpClientAdapter = TestAdapter((_) {
            calls++;
            return reply(null);
          }),
      );
      addTearDown(transfer.close);
      await expectLater(
        transfer.upload(TransferPermit(bad[i], 'PUT'), sample, null),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 0);
    });
  }
  test('上传重定向拒绝，错误不包含签名或服务端正文', () async {
    final transfer = StorageTransfer(
      {'https://storage.example.invalid'},
      dio: Dio()
        ..httpClientAdapter = TestAdapter(
          (_) => ResponseBody.fromString('private-response-secret', 302),
        ),
    );
    addTearDown(transfer.close);
    await expectLater(
      transfer.upload(TransferPermit(permit(), 'PUT'), sample, null),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.message,
          'safe',
          '文件传输未完成，请重试本次上传。',
        ),
      ),
    );
  });
}

void retryTests() {
  test('登记响应丢失后只重试原票据，不再申请或上传', () async {
    var presigns = 0;
    var puts = 0;
    var registrations = 0;
    final api = ApiSession(
      'https://api.example.invalid',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((options) {
          if (options.path == '/auth/login') return reply(tokens());
          if (options.path.endsWith('/presign')) {
            presigns++;
            return reply(permit());
          }
          registrations++;
          expect((options.data as Map)['uploadId'], 'ticket-1');
          if (registrations == 1) {
            throw DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout,
            );
          }
          return reply(document());
        }),
    );
    final transfer = StorageTransfer(
      {'https://storage.example.invalid'},
      dio: Dio()
        ..httpClientAdapter = TestAdapter((_) {
          puts++;
          return ResponseBody.fromString('', 200);
        }),
    );
    final repository = ApiDocuments(api, transfer);
    addTearDown(() {
      repository.close();
      api.close();
    });
    await api.login('fictional@example.invalid', 'fictional-password');
    final upload = repository.beginUpload('case-1', sample, 'EVIDENCE');
    await expectLater(upload.resume(), throwsA(isA<ApiFailure>()));
    expect(upload.bytesUploaded, true);
    expect((await upload.resume()).id, 'doc-1');
    expect((await upload.resume()).id, 'doc-1');
    expect([presigns, puts, registrations], [1, 1, 2]);
    api.close();
    await expectLater(upload.resume(), throwsA(isA<ApiFailure>()));
  });
}

void cancellationTest() {
  for (final closeSession in [true, false]) {
    test('会话或单个操作取消在途上传 $closeSession，不能继续登记', () async {
      final pending = Completer<ResponseBody>();
      var registrations = 0;
      final api = ApiSession(
        'https://api.example.invalid',
        dio: Dio()
          ..httpClientAdapter = TestAdapter((options) {
            if (options.path == '/auth/login') return reply(tokens());
            if (options.path.endsWith('/presign')) return reply(permit());
            registrations++;
            return reply(document());
          }),
      );
      final repository = ApiDocuments(
        api,
        StorageTransfer({
          'https://storage.example.invalid',
        }, dio: Dio()..httpClientAdapter = TestAdapter((_) => pending.future)),
      );
      addTearDown(repository.close);
      await api.login('fictional@example.invalid', 'fictional-password');
      final upload = repository.beginUpload('case-1', sample, 'EVIDENCE');
      final operation = upload.resume();
      final assertion = expectLater(operation, throwsA(isA<ApiFailure>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (closeSession) {
        api.close();
      } else {
        upload.cancel();
      }
      pending.complete(ResponseBody.fromString('', 200));
      await assertion;
      expect(registrations, 0);
      await expectLater(upload.resume(), throwsA(isA<ApiFailure>()));
      api.close();
    });
  }
}

void downloadTests() {
  for (final actual in [2, 3, 4]) {
    test('下载长度 $actual 与记录精确核对', () async {
      final transfer = StorageTransfer(
        {'https://storage.example.invalid'},
        dio: Dio()
          ..httpClientAdapter = TestAdapter(
            (_) => ResponseBody.fromBytes(List.filled(actual, 1), 200),
          ),
      );
      addTearDown(transfer.close);
      final operation = transfer.download(
        TransferPermit(permit(method: 'GET'), 'GET'),
        3,
        (stream) => stream.drain<void>(),
      );
      if (actual == 3) {
        await operation;
      } else {
        await expectLater(operation, throwsA(isA<ApiFailure>()));
      }
    });
  }
}

void downloadCleanupTests() {
  for (final failure in ['early', 'consumer', 'status', 'session']) {
    test('下载失败 $failure 不误报成功并关闭未读响应', () async {
      var closed = false;
      final bytes = StreamController<Uint8List>();
      final transfer = StorageTransfer(
        {'https://storage.example.invalid'},
        dio: Dio()
          ..httpClientAdapter = TestAdapter(
            (_) => ResponseBody(
              bytes.stream,
              failure == 'status' ? 403 : 200,
              onClose: () => closed = true,
            ),
          ),
      );
      addTearDown(transfer.close);
      final operation = transfer.download(
        TransferPermit(permit(method: 'GET'), 'GET'),
        3,
        (stream) async {
          if (failure == 'consumer') throw StateError('fixture');
          if (failure == 'session') {
            transfer.close();
            await stream.drain<void>();
          }
        },
      );
      await expectLater(operation, throwsA(isA<ApiFailure>()));
      await Future<void>.delayed(Duration.zero);
      expect(closed, true);
      await bytes.close();
    });
  }
}
