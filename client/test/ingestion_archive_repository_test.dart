import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_ingestion_archive.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/ingestion_wire.dart';
import 'api_fixture.dart';
import 'ingestion_fixture.dart';
import 'ingestion_archive_fixture.dart';

void main() {
  protocol();
  revision();
  memory();
}

void protocol() {
  test('归档去向严格解析，撤回只提交本次案件文档；未确认响应拒绝', () async {
    final requests = <RequestOptions>[];
    var response = <String, Object?>{
      'state': 'AVAILABLE',
      'caseId': 'case',
      'caseNo': '虚构案号',
      'court': '虚构法院',
      'documentId': 'document',
      'category': 'SERVICE_CONTRACT',
      'canWithdraw': true,
    };
    final session = ApiSession(
      'http://127.0.0.1:3000',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((r) {
          requests.add(r);
          return reply(r.path == '/auth/login' ? tokens() : response);
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final api = ApiIngestionArchive(session);
    final view = await api.locate('in/box');
    expect(requests.last.path, '/ingestion/in%2Fbox/assignment');
    expect(view.target!.caseNo, '虚构案号');
    expect(view.canWithdraw, true);
    for (final changes in [
      {'category': 'bad'},
      {'canWithdraw': null},
      {'documentId': ''},
      {'state': 'BAD'},
    ]) {
      final good = response;
      response = {...response, ...changes};
      await expectLater(api.locate('in/box'), throwsA(isA<ApiFailure>()));
      response = good;
    }
    response = {'withdrawn': true, 'status': 'PENDING_MATCH'};
    expect(await api.withdraw('in/box', view.receipt!), 'PENDING_MATCH');
    expect(requests.last.data, {'caseId': 'case', 'documentId': 'document'});
    response = {'withdrawn': true, 'status': 'ASSIGNED'};
    await expectLater(
      api.withdraw('in/box', view.receipt!),
      throwsA(isA<ApiFailure>()),
    );
    response = {'state': 'UNAVAILABLE'};
    expect((await api.locate('in/box')).target, isNull);
    response = {'state': 'UNASSIGNED'};
    expect((await api.locate('in/box')).receipt, isNull);
    session.close();
    await expectLater(api.locate('in/box'), throwsA(isA<ApiFailure>()));
  });
}

void revision() {
  test('旧响应默认版本零，损坏版本拒绝；合法新版本进入材料实体', () {
    expect(readIngestionItem(ingestionRow()).assignmentRevision, 0);
    expect(
      readIngestionItem({
        ...ingestionRow(),
        'assignmentRevision': 3,
      }).assignmentRevision,
      3,
    );
    for (final revision in [-1, 1.5, '1', null, 2147483648]) {
      expect(
        () => readIngestionItem({
          ...ingestionRow(),
          'assignmentRevision': revision,
        }),
        throwsA(isA<ApiFailure>()),
      );
    }
  });
}

void memory() {
  test('虚构去向、并发撤回、重新分类和旧请求保护，与原件元数据分离', () async {
    final f = ArchiveFixture();
    await f.prepare();
    final view = await f.locate(f.id);
    await Future.wait([
      f.memory.withdraw(f.id, view.receipt!),
      f.memory.withdraw(f.id, view.receipt!),
    ]);
    expect((await f.assigned.experience.load()).single.files, isEmpty);
    final item = await f.assigned.inbox.detail(f.id);
    expect(item.assignmentRevision, 1);
    expect(item.file!.name, '虚构服务合同示例.pdf');
    await expectLater(
      f.assigned.repository.assign(f.id, f.assigned.caseId, 'SERVICE_CONTRACT'),
      throwsA(isA<ApiFailure>()),
    );
    final result = await f.assigned.repository.assign(
      f.id,
      f.assigned.caseId,
      'COURT_DOCUMENT',
      revision: 1,
    );
    expect(result.documentId, isNot(view.receipt!.documentId));
    await expectLater(
      f.memory.withdraw(f.id, view.receipt!),
      throwsA(isA<ApiFailure>()),
    );
    expect((await f.memory.locate(f.id)).receipt!.category, 'COURT_DOCUMENT');
    await f.memory.withdraw(f.id, result);
    await f.assigned.inbox.ignore(f.id);
    expect(await f.memory.withdraw(f.id, result), 'IGNORED');
  });
  test('删除案件或文件不会伪造去向，也不能撤回他人的文档身份', () async {
    final f = ArchiveFixture();
    await f.prepare();
    final view = await f.locate(f.id);
    await f.assigned.experience.removeFile(
      f.assigned.caseId,
      view.receipt!.documentId,
    );
    expect((await f.locate(f.id)).state, 'UNAVAILABLE');
    await expectLater(
      f.memory.withdraw(f.id, view.receipt!),
      throwsA(isA<ApiFailure>()),
    );
    await f.assigned.experience.remove(f.assigned.caseId);
    expect((await f.locate(f.id)).state, 'UNAVAILABLE');
    expect((await f.assigned.inbox.detail(f.id)).status, 'ASSIGNED');
  });
}
