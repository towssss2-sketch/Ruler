import 'dart:convert';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/domain/ingestion_assignment.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_ingestion.dart';
import 'package:ruler_client/infrastructure/api_ingestion_archive.dart';
import 'package:ruler_client/infrastructure/api_ingestion_assignment.dart';
import 'package:ruler_client/infrastructure/api_documents.dart';
import 'package:ruler_client/infrastructure/storage_transfer.dart';
import 'connected_e2e.dart' show check;

Future<void> returnArchiveScenario(
  ApiSession session,
  String id,
  AssignmentReceipt original,
  String storage,
  List<int> bytes,
) async {
  final archive = ApiIngestionArchive(session);
  final assignment = ApiIngestionAssignment(session, ApiRepository(session));
  final inbox = ApiIngestion(session);
  final view = await archive.locate(id);
  check(
    view.target!.id == original.caseId &&
        view.receipt!.documentId == original.documentId &&
        view.canWithdraw,
  );
  check(await archive.withdraw(id, original) == 'PENDING_MATCH');
  check(await archive.withdraw(id, original) == 'PENDING_MATCH');
  check((await archive.locate(id)).state == 'UNASSIGNED');
  final item = await inbox.detail(id);
  check(item.assignmentRevision == 1 && item.status == 'PENDING_MATCH');
  await conflict(
    () => assignment.assign(id, original.caseId, original.category),
  );
  final current = await assignment.assign(
    id,
    original.caseId,
    'COURT_DOCUMENT',
    revision: item.assignmentRevision,
  );
  check(current.documentId != original.documentId);
  await conflict(() => archive.withdraw(id, original));
  check((await archive.locate(id)).receipt!.category == 'COURT_DOCUMENT');
  final files = ApiDocuments(session, StorageTransfer({storage}));
  try {
    final listing = await files.list(original.caseId);
    check(listing.total == 1 && listing.items.single.id == current.documentId);
    await files.download(listing.items.single, (stream) async {
      check(
        base64Encode(await stream.expand((part) => part).toList()) ==
            base64Encode(bytes),
      );
    });
  } finally {
    files.close();
  }
}

Future<void> conflict(Future<Object?> Function() action) async {
  try {
    await action();
  } on ApiFailure catch (_) {
    return;
  }
  throw StateError('旧归档请求未被拒绝');
}
