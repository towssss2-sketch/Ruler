import '../domain/ingestion_assignment.dart';
import '../domain/online.dart';
import '../domain/experience.dart';
import 'memory_ingestion.dart';
import 'experience_query.dart';

/// 同一进程虚构案件和材料，归档元数据没有真实字节；重启不保留。
class MemoryIngestionAssignment implements IngestionAssignment {
  MemoryIngestionAssignment(this.inbox, this.experience, this.refresh);
  final MemoryIngestion inbox;
  final ExperienceRepository experience;
  final Future<void> Function() refresh;
  @override
  Future<OnlinePage<OnlineCase>> cases({
    String keyword = '',
    int page = 1,
  }) async {
    final items = queryExperienceCases(
      await experience.load(),
      keyword: keyword,
    );
    return OnlinePage(
      items
          .skip((page - 1) * 20)
          .take(20)
          .map(
            (item) => OnlineCase(item.id, item.caseNo, item.cause, item.court),
          )
          .toList(),
      items.length,
      page,
    );
  }

  @override
  Future<AssignmentReceipt> assign(
    String id,
    String caseId,
    String category, {
    int revision = 0,
  }) async {
    try {
      final receipt = inbox.assignExample(
        id,
        caseId,
        category,
        (file, receipt, retry) => experience.archiveSample(
          caseId,
          receipt.documentId,
          file.name,
          category,
          retry: retry,
        ),
        revision: revision,
      );
      await refresh();
      return receipt;
    } on ExperienceFailure catch (error) {
      throw ApiFailure(error.message);
    }
  }
}
