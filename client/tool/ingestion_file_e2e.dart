import 'dart:convert';
import 'dart:io';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/ingestion.dart';
import 'package:ruler_client/infrastructure/api_ingestion.dart';
import 'package:ruler_client/infrastructure/api_ingestion_files.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/storage_transfer.dart';
import 'package:ruler_client/infrastructure/file_staging.dart';
import 'connected_e2e.dart' show check, forbidden;

/// 真正的客户端无案件上传/判重/重登/下载/越权；不是协议替身。
Future<void> ingestionFileScenario(
  ApiSession first,
  String ownerEmail,
  String otherEmail,
  String password,
) async {
  final origin = Platform.environment['RULER_E2E_URL']!;
  final storage = Platform.environment['RULER_E2E_STORAGE']!;
  final files = ApiIngestionFiles(first, StorageTransfer({storage}));
  final snapshot = await StagedFile.create(Directory.systemTemp);
  final bytes = await File('tool/fixtures/fictional.pdf').readAsBytes();
  try {
    final digest = await snapshot.receive(
      Stream.value(bytes),
      bytes.length,
      () => true,
    );
    final source = UploadSource(
      name: '虚构待定服务合同.pdf',
      mimeType: 'application/pdf',
      size: bytes.length,
      md5: digest,
      open: snapshot.file.openRead,
    );
    final upload = files.begin(source);
    final receipt = await upload.resume();
    check(
      !receipt.duplicate &&
          receipt.status == 'PENDING_MATCH' &&
          upload.bytesUploaded,
    );
    check((await upload.resume()).id == receipt.id);
    final duplicate = await files.begin(source).resume();
    check(duplicate.duplicate && duplicate.id == receipt.id);
    final inbox = ApiIngestion(first);
    final row = (await inbox.list()).items.single;
    check(
      row.id == receipt.id &&
          row.file!.name == source.name &&
          row.file!.size == bytes.length,
    );
    await compareBytes(files, row.id, row.file!, bytes);
    await reopenAndIsolate(
      origin,
      storage,
      ownerEmail,
      otherEmail,
      password,
      row.id,
      bytes,
    );
    check((await inbox.detail(row.id)).status == 'IGNORED');
    check((await files.begin(source).resume()).status == 'IGNORED');
  } finally {
    files.close();
    await snapshot.dispose();
  }
}

Future<void> reopenAndIsolate(
  String origin,
  String storage,
  String ownerEmail,
  String otherEmail,
  String password,
  String id,
  List<int> bytes,
) async {
  final session = ApiSession(origin);
  final files = ApiIngestionFiles(session, StorageTransfer({storage}));
  final other = ApiSession(origin);
  final isolated = ApiIngestionFiles(other, StorageTransfer({storage}));
  try {
    await session.login(ownerEmail, password);
    final inbox = ApiIngestion(session);
    final row = await inbox.detail(id);
    check(row.file != null && row.file!.size == bytes.length);
    await inbox.ignore(id);
    check(
      (await inbox.list(history: true)).items.any(
        (item) =>
            item.id == id && item.file != null && item.status == 'IGNORED',
      ),
    );
    await files.download(id, row.file!, (stream) async {
      check(
        base64Encode(await stream.expand((b) => b).toList()) ==
            base64Encode(bytes),
      );
    });
    await other.login(otherEmail, password);
    await forbidden(
      () => isolated.download(id, row.file!, (stream) => stream.drain<void>()),
    );
    await forbidden(() async {
      await ApiIngestion(other).detail(id);
    });
    await session.logout();
    await other.logout();
  } finally {
    files.close();
    isolated.close();
    session.close();
    other.close();
  }
}

Future<void> compareBytes(
  ApiIngestionFiles files,
  String id,
  IngestionFile file,
  List<int> bytes,
) async {
  await files.download(id, file, (stream) async {
    check(
      base64Encode(await stream.expand((b) => b).toList()) ==
          base64Encode(bytes),
    );
  });
}
