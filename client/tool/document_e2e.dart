import 'dart:convert';
import 'dart:io';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/infrastructure/api_documents.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/storage_transfer.dart';
import 'package:ruler_client/infrastructure/file_staging.dart';
import 'connected_e2e.dart' show check, forbidden;

/// 真实 MinIO PUT→登记→下载逐字节比较→版本与删除，全部虚构内容。
Future<List<String>> documentScenarios(
  ApiSession session,
  String caseId,
  String ownEmail,
  String otherEmail,
  String password,
) async {
  final origin = Platform.environment['RULER_E2E_URL']!;
  final storage = Platform.environment['RULER_E2E_STORAGE']!;
  final documents = ApiDocuments(session, StorageTransfer({storage}));
  final fixture = File('tool/fixtures/fictional.pdf');
  final bytes = await fixture.readAsBytes();
  final snapshot = await StagedFile.create(Directory.systemTemp);
  final digest = await snapshot.receive(
    fixture.openRead(),
    bytes.length,
    () => true,
  );
  final source = UploadSource(
    name: '虚构传输测试.pdf',
    mimeType: 'application/pdf',
    size: bytes.length,
    md5: digest,
    open: snapshot.file.openRead,
  );
  try {
    final first = await roundTrip(documents, caseId, source, bytes);
    check((await documents.list(caseId)).total == 1);
    await versions(documents, caseId, source, first);
    await reopen(origin, storage, ownEmail, password, caseId, first);
    await documentIsolation(
      origin,
      storage,
      otherEmail,
      password,
      caseId,
      first,
    );
    return [
      '真实 MinIO 上传、登记与下载逐字节一致',
      '文件分类、历史版本、删除后恢复与新实例重登保留',
      '第二账号不能列表、下载或删除他人文件',
    ];
  } finally {
    documents.close();
    await snapshot.dispose();
  }
}

/// 新客户端登录后读取正式文件；不是同一个仓库对象的内存缓存。
Future<void> reopen(
  String origin,
  String storage,
  String email,
  String password,
  String caseId,
  CaseDocument file,
) async {
  final session = ApiSession(origin);
  final documents = ApiDocuments(session, StorageTransfer({storage}));
  try {
    await session.login(email, password);
    check((await documents.list(caseId)).items.single.id == file.id);
    await documents.download(file, (stream) => stream.drain<void>());
    await session.logout();
  } finally {
    documents.close();
    session.close();
  }
}

/// 真实历史版本列表与软删除恢复，不清理既有应用对象。
Future<void> versions(
  ApiDocuments documents,
  String caseId,
  UploadSource source,
  CaseDocument first,
) async {
  final second = await documents
      .beginUpload(caseId, source, 'EVIDENCE', previousId: first.id)
      .resume();
  check(second.version == 2);
  check((await documents.list(caseId)).items.single.id == second.id);
  check((await documents.list(caseId, history: true)).total == 2);
  check((await documents.list(caseId, category: 'OTHER')).total == 0);
  await documents.remove(second.id);
  check((await documents.list(caseId)).items.single.id == first.id);
}

/// 第二个真实账号验证文件资源权限，禁止向对象存储绕过鉴权下载。
Future<void> documentIsolation(
  String origin,
  String storage,
  String email,
  String password,
  String caseId,
  CaseDocument file,
) async {
  final session = ApiSession(origin);
  final documents = ApiDocuments(session, StorageTransfer({storage}));
  try {
    await session.login(email, password);
    await forbidden(() async {
      await documents.list(caseId);
    });
    await forbidden(() => documents.remove(file.id));
    await forbidden(
      () => documents.download(file, (stream) => stream.drain<void>()),
    );
    await session.logout();
  } finally {
    documents.close();
    session.close();
  }
}

/// 使用实际快照和客户端摘要上传，再将完整下载写入实际临时文件。
Future<CaseDocument> roundTrip(
  ApiDocuments documents,
  String caseId,
  UploadSource source,
  List<int> bytes,
) async {
  final pending = documents.beginUpload(caseId, source, 'EVIDENCE');
  final first = await pending.resume();
  check((await pending.resume()).id == first.id);
  final downloaded = await StagedFile.create(Directory.systemTemp);
  try {
    await documents.download(first, (stream) async {
      await downloaded.receive(stream, first.size, () => true);
    });
    check(
      base64Encode(await downloaded.file.readAsBytes()) == base64Encode(bytes),
    );
    return first;
  } finally {
    await downloaded.dispose();
  }
}
