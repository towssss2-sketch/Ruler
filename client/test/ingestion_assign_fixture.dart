import 'dart:async';
import 'package:ruler_client/domain/ingestion_assignment.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'ingestion_file_widget_fixture.dart' show FileInboxFixture;
import 'package:ruler_client/infrastructure/memory_ingestion_assignment.dart';

class AssignmentFixture implements IngestionAssignment {
  final inbox = FileInboxFixture();
  final experience = MemoryExperience();
  late final repository = MemoryIngestionAssignment(
    inbox,
    experience,
    () async {},
  );
  int attempts = 0;
  bool failCases = false,
      failAssign = false,
      loseResponse = false,
      failAfterWrite = false;
  Completer<void>? gate;
  late String caseId;
  final queries = <String>[];
  Future<void> prepare() async {
    caseId = await experience.create('(2026)虚构民初90号', '虚构归档纠纷', '虚构法院');
    await inbox.addFileExample();
  }

  @override
  Future<OnlinePage<OnlineCase>> cases({
    String keyword = '',
    int page = 1,
    String? caseNo,
  }) async {
    queries.add(caseNo == null ? '$keyword:$page' : 'exact:$caseNo:$page');
    if (failCases) throw const ApiFailure('案件列表暂不可用。');
    return repository.cases(keyword: keyword, page: page, caseNo: caseNo);
  }

  @override
  Future<AssignmentReceipt> assign(
    String id,
    String caseId,
    String category, {
    int revision = 0,
  }) async {
    attempts++;
    await gate?.future;
    if (failAssign) throw const ApiFailure('归档失败，请保留选择重试。');
    final result = await repository.assign(
      id,
      caseId,
      category,
      revision: revision,
    );
    if (loseResponse) {
      loseResponse = false;
      throw const ApiFailure('归档结果未确认，请重试。');
    }
    if (failAfterWrite) inbox.failRead = true;
    return result;
  }
}
