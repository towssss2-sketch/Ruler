import 'package:dio/dio.dart';
import 'ingestion_fixture.dart';
import 'api_fixture.dart';
import 'dart:async';
import 'package:ruler_client/domain/ingestion_archive.dart';
import 'package:ruler_client/domain/ingestion_assignment.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/memory_ingestion_archive.dart';
import 'ingestion_assign_fixture.dart';

class ArchiveFixture implements IngestionArchive {
  final assigned = AssignmentFixture();
  late final memory = MemoryIngestionArchive(
    assigned.inbox,
    assigned.experience,
    () async {},
  );
  late String id;
  bool failRead = false,
      failWrite = false,
      loseReply = false,
      failList = false,
      unavailable = false,
      blocked = false;
  int writes = 0;
  Completer<void>? gate;
  Future<void> prepare() async {
    await assigned.prepare();
    id = (await assigned.inbox.list()).items.single.id;
    await assigned.repository.assign(id, assigned.caseId, 'SERVICE_CONTRACT');
  }

  @override
  Future<ArchiveLocation> locate(String id) async {
    if (failRead) throw const ApiFailure('去向暂不可用。');
    if (unavailable) return const ArchiveLocation('UNAVAILABLE');
    final location = await memory.locate(id);
    if (!blocked) return location;
    return ArchiveLocation(
      location.state,
      target: location.target,
      receipt: location.receipt,
    );
  }

  @override
  Future<String> withdraw(String id, AssignmentReceipt receipt) async {
    writes++;
    await gate?.future;
    if (failWrite) throw const ApiFailure('撤回未完成，请重试。');
    final result = await memory.withdraw(id, receipt);
    if (loseReply) {
      loseReply = false;
      throw const ApiFailure('撤回结果未确认，请重试。');
    }
    if (failList) assigned.inbox.failRead = true;
    return result;
  }
}

class ArchiveSessionFixture extends IngestionFixture {
  @override
  ResponseBody handle(RequestOptions request) {
    if (!expire && request.path.endsWith('/assignment')) {
      return reply({
        'state': 'AVAILABLE',
        'caseId': 'case',
        'caseNo': '虚构案号',
        'court': '虚构法院',
        'documentId': 'document',
        'category': 'SERVICE_CONTRACT',
        'canWithdraw': true,
      });
    }
    return super.handle(request);
  }
}
