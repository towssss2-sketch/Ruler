import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/case_fields.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'api_fixture.dart';

const fields = CaseFields(
  caseNo: '(2026)虚构民初3号',
  cause: '虚构修改',
  court: '虚构法院',
  stage: 'RETRIAL',
  status: 'CLOSED',
);

void main() {
  test('PATCH 仅发送五个基础字段，编码路径并解析服务器规范化结果', () async {
    Map<String, Object?>? sent;
    String? path;
    final session = ApiSession(
      'https://example.invalid',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((request) {
          if (request.path == '/auth/login') return reply(tokens());
          expect(request.method, 'PATCH');
          sent = request.data as Map<String, Object?>;
          path = request.path;
          return reply({
            'id': 'fictional',
            ...fields.toJson(),
            'caseNo': '(2026)虚构民初4号',
          });
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final saved = await ApiRepository(
      session,
    ).updateCase('fictional/one', fields);
    expect(path, '/cases/fictional%2Fone');
    expect(sent, fields.toJson());
    expect(
      sent!.keys,
      unorderedEquals(['caseNo', 'cause', 'court', 'stage', 'status']),
    );
    expect(saved.caseNo, '(2026)虚构民初4号');
    expect(saved.stage, 'RETRIAL');
    expect(saved.status, 'CLOSED');
  });
  for (final invalid in [
    {'stage': 'UNKNOWN'},
    {'status': 'ARCHIVED'},
    {'stage': null},
  ]) {
    test('未知或缺失枚举拒绝显示为有效案件：${invalid.keys.single}', () async {
      final session = ApiSession(
        'https://example.invalid',
        dio: Dio()
          ..httpClientAdapter = TestAdapter(
            (request) => request.path == '/auth/login'
                ? reply(tokens())
                : reply({'id': 'fictional', ...fields.toJson(), ...invalid}),
          ),
      );
      addTearDown(session.close);
      await session.login('fictional@example.invalid', 'fictional-password');
      await expectLater(
        ApiRepository(session).updateCase('fictional', fields),
        throwsA(
          isA<ApiFailure>().having((e) => e.message, 'safe', '服务响应格式异常。'),
        ),
      );
    });
  }
  memoryEdit();
  test('案号统一括号与空白，允许后端支持的汉字并拒绝格式错误', () {
    expect(normalizeCaseNumber(' （2026） 虚构民初1号 '), '(2026)虚构民初1号');
    expect(validateCaseNumber('(2026)𠀀民初1号'), isNull);
    expect(validateCaseNumber('(2026)ABC1号'), isNotNull);
    expect(validateCaseNumber('(2026)虚构民初1'), isNotNull);
  });
}

void memoryEdit() {
  test('离线编辑保留关联记录及旧快照；重复、非法和已删除案件均拒绝', () async {
    final repository = MemoryExperience();
    final id = await repository.create('(2026)虚构民初1号', '虚构', '虚构法院');
    final other = await repository.create('(2026)虚构民初3号', '虚构', '虚构法院');
    await repository.addSample(id, category: 'SERVICE_CONTRACT');
    await repository.addTask(id, '虚构待办');
    final original = (await repository.load()).last;
    await expectLater(repository.update(id, fields), throwsException);
    expect((await repository.load()).last.caseNo, original.caseNo);
    await repository.remove(other);
    await repository.update(id, fields);
    final saved = (await repository.load()).single;
    expect(saved.caseNo, fields.caseNo);
    expect(saved.stage, fields.stage);
    expect(saved.status, fields.status);
    expect(saved.tasks.single.id, original.tasks.single.id);
    expect(saved.tasks.single.done, isFalse);
    expect(saved.files.single.id, original.files.single.id);
    expect(saved.files.single.category, 'SERVICE_CONTRACT');
    expect(original.caseNo, '(2026)虚构民初1号');
    await expectLater(
      repository.update(
        id,
        const CaseFields(caseNo: '非法', cause: '虚构', court: '虚构'),
      ),
      throwsException,
    );
    expect((await repository.load()).single.caseNo, fields.caseNo);
    await repository.remove(id);
    await expectLater(repository.update(id, fields), throwsException);
  });
}
