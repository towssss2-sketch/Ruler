import 'online.dart';

class AssignmentReceipt {
  const AssignmentReceipt(this.documentId, this.caseId, this.category);
  final String documentId, caseId, category;
}

abstract interface class IngestionAssignment {
  Future<OnlinePage<OnlineCase>> cases({
    String keyword = '',
    int page = 1,
    String? caseNo,
  });
  Future<AssignmentReceipt> assign(
    String id,
    String caseId,
    String category, {
    int revision = 0,
  });
}
