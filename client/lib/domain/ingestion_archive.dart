import 'ingestion_assignment.dart';
import 'online.dart';

class ArchiveLocation {
  const ArchiveLocation(
    this.state, {
    this.target,
    this.receipt,
    this.canWithdraw = false,
  });
  final String state;
  final OnlineCase? target;
  final AssignmentReceipt? receipt;
  final bool canWithdraw;
}

abstract interface class IngestionArchive {
  Future<ArchiveLocation> locate(String id);
  Future<String> withdraw(String id, AssignmentReceipt receipt);
}
