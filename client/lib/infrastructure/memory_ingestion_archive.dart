import '../domain/ingestion_archive.dart';
import '../domain/ingestion_assignment.dart';
import '../domain/experience.dart';
import '../domain/online.dart';
import 'memory_ingestion.dart';

class MemoryIngestionArchive implements IngestionArchive {
  MemoryIngestionArchive(this.inbox, this.experience, this.refresh);
  final MemoryIngestion inbox;
  final ExperienceRepository experience;
  final Future<void> Function() refresh;
  @override
  Future<ArchiveLocation> locate(String id) async {
    final item = await inbox.detail(id);
    if (item.status != 'ASSIGNED') return const ArchiveLocation('UNASSIGNED');
    final receipt = inbox.currentAssignment(id);
    final records = await experience.load();
    final target = records
        .where((item) => item.id == receipt?.caseId)
        .firstOrNull;
    final file = target?.files
        .where((file) => file.id == receipt?.documentId)
        .firstOrNull;
    if (receipt == null || target == null || file == null) {
      return const ArchiveLocation('UNAVAILABLE');
    }
    return ArchiveLocation(
      'AVAILABLE',
      target: OnlineCase(target.id, target.caseNo, target.cause, target.court),
      receipt: receipt,
      canWithdraw: !target.files.any(
        (other) => other.id != file.id && other.group == file.group,
      ),
    );
  }

  @override
  Future<String> withdraw(String id, AssignmentReceipt receipt) async {
    try {
      final status = inbox.withdrawExample(
        id,
        receipt,
        () => experience.withdrawSample(receipt.caseId, receipt.documentId),
      );
      await refresh();
      return status;
    } on ExperienceFailure catch (error) {
      throw ApiFailure(error.message);
    }
  }
}
