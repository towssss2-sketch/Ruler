import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/infrastructure/api_ingestion.dart';
import 'package:ruler_client/infrastructure/api_ingestion_files.dart';
import 'package:ruler_client/infrastructure/api_ingestion_preview.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'connected_e2e.dart' show check;

/// 读取数据库中的实际尝试；反复查询不增加记录，分页越界为空。
Future<void> verifyPreviewAttempts(
  ApiSession session,
  String id,
  int count,
) async {
  final api = ApiIngestionPreview(session);
  final page = await api.attempts(id);
  check(page.total == count && page.items.length == count);
  check(
    page.items.every(
      (item) =>
          item.status == 'SUCCEEDED' &&
          !item.retryable &&
          item.finishedAt != null,
    ),
  );
  check((await api.attempts(id)).total == count);
  check((await api.attempts(id, page: 2)).items.isEmpty);
}

/// 真正上传损坏 PDF，解析器给固定失败原因；失败历史不丢，重新提取产生独立记录。
Future<void> verifyFailedAttempts(
  ApiSession session,
  ApiIngestionFiles files,
) async {
  final bytes = utf8.encode('%PDF-1.7\ninvalid fictional document');
  final receipt = await files
      .begin(
        UploadSource(
          name: '虚构损坏材料.pdf',
          mimeType: 'application/pdf',
          size: bytes.length,
          md5: base64Encode(md5.convert(bytes).bytes),
          open: () => Stream.value(bytes),
        ),
      )
      .resume();
  final api = ApiIngestionPreview(session);
  for (var i = 0; i < 2; i++) {
    final result = await api.preview(receipt.id);
    check(result.reason == 'INVALID_DOCUMENT' && !result.retryable);
  }
  final history = await api.attempts(receipt.id);
  check(history.total == 2 && history.items[0].id != history.items[1].id);
  check(
    history.items.every(
      (item) =>
          item.status == 'MANUAL_REQUIRED' &&
          item.reason == 'INVALID_DOCUMENT' &&
          !item.retryable,
    ),
  );
  check(
    (await ApiIngestion(session).detail(receipt.id)).status == 'PENDING_MATCH',
  );
  await ApiIngestion(session).ignore(receipt.id);
  check((await api.attempts(receipt.id)).total == 2);
}
