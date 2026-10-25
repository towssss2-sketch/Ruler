import '../domain/ingestion_archive.dart';
import '../domain/ingestion_assignment.dart';
import '../domain/documents.dart';
import '../domain/online.dart';
import 'api_session.dart';

class ApiIngestionArchive implements IngestionArchive {
  ApiIngestionArchive(this.session);
  final ApiSession session;
  @override
  Future<ArchiveLocation> locate(String id) async {
    final row = jsonObject(
      await session.request(
        'GET',
        '/ingestion/${Uri.encodeComponent(id)}/assignment',
      ),
    );
    if (row['state'] == 'UNASSIGNED' || row['state'] == 'UNAVAILABLE') {
      return ArchiveLocation(row['state'] as String);
    }
    if (row['state'] != 'AVAILABLE' ||
        row['canWithdraw'] is! bool ||
        !documentCategories.containsKey(row['category'])) {
      throw const ApiFailure('归档去向格式异常，请刷新重试。');
    }
    final caseId = jsonText(row, 'caseId');
    return ArchiveLocation(
      'AVAILABLE',
      target: OnlineCase(
        caseId,
        jsonText(row, 'caseNo'),
        '',
        jsonText(row, 'court'),
      ),
      receipt: AssignmentReceipt(
        jsonText(row, 'documentId'),
        caseId,
        row['category'] as String,
      ),
      canWithdraw: row['canWithdraw'] as bool,
    );
  }

  @override
  Future<String> withdraw(String id, AssignmentReceipt receipt) async {
    final row = jsonObject(
      await session.request(
        'POST',
        '/ingestion/${Uri.encodeComponent(id)}/withdraw',
        data: {'caseId': receipt.caseId, 'documentId': receipt.documentId},
      ),
    );
    if (row['withdrawn'] != true ||
        !['PENDING_MATCH', 'IGNORED'].contains(row['status'])) {
      throw const ApiFailure('撤回结果未确认，请重试或刷新核对。');
    }
    return row['status'] as String;
  }
}
