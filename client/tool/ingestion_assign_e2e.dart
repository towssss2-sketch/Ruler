import 'dart:convert';
import 'dart:io';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/ingestion_files.dart';
import 'package:ruler_client/infrastructure/api_ingestion.dart';
import 'package:ruler_client/infrastructure/api_ingestion_files.dart';
import 'package:ruler_client/infrastructure/api_ingestion_assignment.dart';
import 'package:ruler_client/infrastructure/api_documents.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/file_staging.dart';
import 'package:ruler_client/infrastructure/storage_transfer.dart';
import 'connected_e2e.dart' show check, forbidden;

/// 真实字节上传、人工选案件/分类、幂等归档、重登按类下载与资源隔离。
Future<void> ingestionAssignScenario(
  ApiSession first,
  String ownerEmail,
  String otherEmail,
  String password,
) async {
  final storage = Platform.environment['RULER_E2E_STORAGE']!;
  final inbox = ApiIngestion(first);
  final repository = ApiRepository(first);
  final assignment = ApiIngestionAssignment(first, repository);
  final target = await repository.createCase(
    '(2026)虚构民初989号',
    '虚构归档纠纷',
    '虚构归档法院',
    '虚构归档甲',
  );
  check(
    (await assignment.cases(keyword: '虚构归档甲')).items.single.id == target.id,
  );
  final files = ApiIngestionFiles(first, StorageTransfer({storage}));
  final snapshot = await StagedFile.create(Directory.systemTemp);
  final bytes = [
    ...await File('tool/fixtures/fictional.pdf').readAsBytes(),
    ...utf8.encode('\n% fictional-assignment\n'),
  ];
  try {
    final upload = await uploadAssignment(files, snapshot, bytes);
    final receipt = await assignment.assign(
      upload.id,
      target.id,
      'SERVICE_CONTRACT',
    );
    check(
      (await assignment.assign(
            upload.id,
            target.id,
            'SERVICE_CONTRACT',
          )).documentId ==
          receipt.documentId,
    );
    check((await inbox.detail(upload.id)).status == 'ASSIGNED');
    check(!(await inbox.list()).items.any((item) => item.id == upload.id));
    await rereadAssignment(
      Platform.environment['RULER_E2E_URL']!,
      storage,
      ownerEmail,
      otherEmail,
      password,
      upload.id,
      target.id,
      receipt.documentId,
      bytes,
    );
    await repository.removeCase(target.id);
  } finally {
    files.close();
    await snapshot.dispose();
  }
}

Future<void> rereadAssignment(
  String origin,
  String storage,
  String email,
  String otherEmail,
  String password,
  String id,
  String caseId,
  String documentId,
  List<int> bytes,
) async {
  final session = ApiSession(origin);
  final other = ApiSession(origin);
  final files = ApiDocuments(session, StorageTransfer({storage}));
  try {
    await session.login(email, password);
    final list = await files.list(caseId, category: 'SERVICE_CONTRACT');
    check(list.total == 1 && list.items.single.id == documentId);
    await files.download(list.items.single, (stream) async {
      check(
        base64Encode(await stream.expand((part) => part).toList()) ==
            base64Encode(bytes),
      );
    });
    check(
      (await ApiIngestion(session).list(
        history: true,
      )).items.any((item) => item.id == id && item.status == 'ASSIGNED'),
    );
    await other.login(otherEmail, password);
    await forbidden(
      () => ApiIngestionAssignment(
        other,
        ApiRepository(other),
      ).assign(id, caseId, 'SERVICE_CONTRACT'),
    );
    await forbidden(
      () => other.request('GET', '/documents/$documentId/download'),
    );
    await session.logout();
    await other.logout();
  } finally {
    files.close();
    session.close();
    other.close();
  }
}

Future<IngestionFileReceipt> uploadAssignment(
  ApiIngestionFiles files,
  StagedFile snapshot,
  List<int> bytes,
) async {
  final digest = await snapshot.receive(
    Stream.value(bytes),
    bytes.length,
    () => true,
  );
  return await files
      .begin(
        UploadSource(
          name: '虚构归档服务合同.pdf',
          mimeType: 'application/pdf',
          size: bytes.length,
          md5: digest,
          open: snapshot.file.openRead,
        ),
      )
      .resume();
}
