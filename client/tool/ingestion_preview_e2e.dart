import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/infrastructure/api_ingestion.dart';
import 'package:ruler_client/infrastructure/api_ingestion_files.dart';
import 'package:ruler_client/infrastructure/api_ingestion_preview.dart';
import 'package:ruler_client/infrastructure/api_ingestion_assignment.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/storage_transfer.dart';
import 'connected_e2e.dart' show check, forbidden;
import 'case_match_e2e.dart';
import 'preview_attempt_e2e.dart';

/// 真正上传有效 PDF/DOCX，由服务器解析；同一客户端仓库读取结果，不使用协议替身。
Future<void> ingestionPreviewScenario(
  ApiSession first,
  String ownerEmail,
  String otherEmail,
  String password,
) async {
  // 新场景与原有请求共用真实限流；自然跨窗口，不清空 Redis 或放宽服务规则。
  await Future<void>.delayed(const Duration(seconds: 61));
  final files = ApiIngestionFiles(
    first,
    StorageTransfer({Platform.environment['RULER_E2E_STORAGE']!}),
  );
  try {
    await verifyFailedAttempts(first, files);
    for (final extension in ['pdf', 'docx']) {
      final result = await previewFile(first, files, extension);
      if (extension == 'docx') {
        await previewReopen(result.id, ownerEmail, otherEmail, password);
        await confirmSuggestion(
          first,
          result.id,
          result.category!,
          result.number!,
          otherEmail,
          password,
        );
      } else {
        await ApiIngestion(first).ignore(result.id);
      }
    }
  } finally {
    files.close();
  }
}

Future<({String id, String? category, String? number})> previewFile(
  ApiSession session,
  ApiIngestionFiles files,
  String extension,
) async {
  final bytes = await File(
    'tool/fixtures/fictional-preview.$extension',
  ).readAsBytes();
  final receipt = await files
      .begin(
        UploadSource(
          name: '虚构正文.$extension',
          mimeType: extension == 'pdf'
              ? 'application/pdf'
              : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          size: bytes.length,
          md5: base64Encode(md5.convert(bytes).bytes),
          open: () => Stream.value(bytes),
        ),
      )
      .resume();
  final api = ApiIngestionPreview(session), inbox = ApiIngestion(session);
  final result = await api.preview(receipt.id);
  check(result.text != null && result.reason == null);
  check(
    result.text!.contains(
      extension == 'pdf' ? 'Fictional preview document only' : '本文件仅用于虚构联调。',
    ),
  );
  check(
    result.suggestion!.category ==
        (extension == 'pdf' ? null : 'SERVICE_CONTRACT'),
  );
  if (extension == 'docx') {
    check(result.suggestion!.caseNumbers.single == '(2026)虚构民初90号');
  }
  check((await api.preview(receipt.id)).attemptId != result.attemptId);
  await verifyPreviewAttempts(session, receipt.id, 2);
  final row = await inbox.detail(receipt.id);
  check(row.status == 'PENDING_MATCH' && row.assignmentRevision == 0);
  await files.download(row.id, row.file!, (stream) async {
    check(
      base64Encode(await stream.expand((part) => part).toList()) ==
          base64Encode(bytes),
    );
  });
  return (
    id: receipt.id,
    category: result.suggestion!.category,
    number: result.suggestion!.caseNumbers.firstOrNull,
  );
}

Future<void> previewReopen(
  String id,
  String email,
  String otherEmail,
  String password,
) async {
  final origin = Platform.environment['RULER_E2E_URL']!;
  final reopened = ApiSession(origin), other = ApiSession(origin);
  try {
    await reopened.login(email, password);
    await verifyPreviewAttempts(reopened, id, 2);
    check(
      (await ApiIngestionPreview(reopened).preview(id)).suggestion!.category ==
          'SERVICE_CONTRACT',
    );
    await other.login(otherEmail, password);
    await forbidden(() async {
      await ApiIngestionPreview(other).preview(id);
    });
    await forbidden(() async {
      await ApiIngestionPreview(other).attempts(id);
    });
    await reopened.logout();
    await other.logout();
  } finally {
    reopened.close();
    other.close();
  }
}

Future<void> confirmSuggestion(
  ApiSession session,
  String id,
  String category,
  String number,
  String otherEmail,
  String password,
) async {
  final repository = ApiRepository(session);
  final target = await repository.createCase(number, '虚构正文确认', '虚构法院', '虚构甲');
  try {
    final matchedId = await verifyCaseNumberMatch(
      session,
      number,
      target.id,
      otherEmail,
      password,
    );
    final document = await ApiIngestionAssignment(
      session,
      repository,
    ).assign(id, matchedId, category);
    check(document.category == 'SERVICE_CONTRACT');
    check((await ApiIngestion(session).detail(id)).status == 'ASSIGNED');
    check(
      (await ApiIngestionPreview(session).preview(id)).suggestion!.category ==
          category,
    );
  } finally {
    await repository.removeCase(target.id);
  }
}
