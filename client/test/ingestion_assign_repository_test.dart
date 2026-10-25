import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_ingestion_assignment.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'api_fixture.dart';
import 'ingestion_assign_fixture.dart';

void main() {
  protocol();
  memory();
  search();
  retainedHistory();
}

void protocol() {
  test('归档只发送案件与分类；路径编码、响应归属和全部分类严格核对', () async {
    final requests = <RequestOptions>[];
    final document = <String, Object?>{
      'id': 'doc',
      'caseId': 'case',
      'ingestionId': 'in/box',
      'source': 'WECHAT',
      'fileName': '虚构.pdf',
      'sizeBytes': '3',
      'version': 1,
      'isCurrentVersion': true,
      'category': 'SERVICE_CONTRACT',
    };
    final session = ApiSession(
      'http://127.0.0.1:3000',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((r) {
          requests.add(r);
          return reply(r.path == '/auth/login' ? tokens() : document);
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final repository = ApiIngestionAssignment(session, ApiRepository(session));
    for (final category in documentCategories.keys) {
      document['category'] = category;
      expect(
        (await repository.assign('in/box', 'case', category)).category,
        category,
      );
      expect(requests.last.path, '/ingestion/in%2Fbox/assign');
      expect(requests.last.data, {
        'caseId': 'case',
        'category': category,
        'revision': 0,
      });
    }
    for (final key in ['caseId', 'ingestionId', 'source', 'category']) {
      final original = document[key];
      document[key] = 'wrong';
      await expectLater(
        repository.assign('in/box', 'case', 'OTHER'),
        throwsA(isA<ApiFailure>()),
      );
      document[key] = original;
    }
    final count = requests.length;
    await expectLater(
      repository.assign('in/box', 'case', 'bad'),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests.length, count);
    session.close();
    await expectLater(
      repository.assign('in/box', 'case', 'OTHER'),
      throwsA(isA<ApiFailure>()),
    );
  });
}

void memory() {
  test('离线真实元数据归入指定类别，重复/并发不增加示例；忽略与改派拒绝', () async {
    for (final category in documentCategories.keys) {
      final f = AssignmentFixture();
      await f.prepare();
      final row = (await f.inbox.list()).items.single;
      await Future.wait([
        f.repository.assign(row.id, f.caseId, category),
        f.repository.assign(row.id, f.caseId, category),
      ]);
      final file = (await f.experience.load()).single.files.single;
      expect(file.name, row.file!.name);
      expect(file.category, category);
      expect(file.version, 1);
      expect((await f.inbox.list()).total, 0);
      expect((await f.inbox.detail(row.id)).status, 'ASSIGNED');
      await expectLater(f.inbox.ignore(row.id), throwsA(isA<ApiFailure>()));
      await expectLater(
        f.repository.assign(row.id, 'wrong', category),
        throwsA(isA<ApiFailure>()),
      );
      expect((await f.inbox.addFileExample()).status, 'ASSIGNED');
    }
  });
  test('不存在案件、文字、忽略状态和错误分类不会污染材料或案件', () async {
    final f = AssignmentFixture();
    await f.prepare();
    final id = (await f.inbox.list()).items.single.id;
    await expectLater(
      f.repository.assign(id, 'missing', 'OTHER'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      f.repository.assign(id, f.caseId, 'bad'),
      throwsA(isA<ApiFailure>()),
    );
    final text = await f.inbox.receive('虚构纯文字');
    await expectLater(
      f.repository.assign(text.id, f.caseId, 'OTHER'),
      throwsA(isA<ApiFailure>()),
    );
    await f.inbox.ignore(id);
    await expectLater(
      f.repository.assign(id, f.caseId, 'OTHER'),
      throwsA(isA<ApiFailure>()),
    );
    expect((await f.experience.load()).single.files, isEmpty);
  });
}

void search() {
  test('案件搜索按关键词和分页读取，空结果不补入其他案件', () async {
    final f = AssignmentFixture();
    await f.prepare();
    for (var i = 0; i < 22; i++) {
      await f.experience.create('(2026)虚构民初${i + 100}号', '虚构分页', '虚构法院');
    }
    expect(
      (await f.repository.cases(keyword: '虚构分页', page: 2)).items.length,
      2,
    );
    expect(
      (await f.repository.cases(keyword: '虚构归档')).items.single.id,
      f.caseId,
    );
    expect((await f.repository.cases(keyword: '不存在')).total, 0);
  });
}

void retainedHistory() {
  test('独立归档示例不覆盖已有分类版本；删除后重试不复活，历史状态保留', () async {
    final f = AssignmentFixture();
    await f.prepare();
    await f.experience.addSample(f.caseId, category: 'SERVICE_CONTRACT');
    final id = (await f.inbox.list()).items.single.id;
    await f.repository.assign(id, f.caseId, 'SERVICE_CONTRACT');
    final files = (await f.experience.load()).single.files;
    expect(files.length, 2);
    expect(files.map((file) => file.group).toSet().length, 2);
    await f.experience.removeFile(f.caseId, id);
    await expectLater(
      f.repository.assign(id, f.caseId, 'SERVICE_CONTRACT'),
      throwsA(isA<ApiFailure>()),
    );
    expect((await f.inbox.detail(id)).status, 'ASSIGNED');
    expect((await f.experience.load()).single.files.length, 1);
  });
}
