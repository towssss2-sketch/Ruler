import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/memory_ingestion.dart';
import 'package:ruler_client/infrastructure/memory_ingestion_preview.dart';
import 'preview_attempt_fixture.dart';
import 'saved_classification_fixture.dart';

void main() {
  test('分类历史只GET指定尝试，编码路径、不传查询参数、不发起提取', () async {
    final f = AttemptProtocol()..response = savedRow();
    addTearDown(f.session.close);
    await f.login();
    final result = await f.api.classification('in/box', savedAttemptId);
    expect(result.category, 'SERVICE_CONTRACT');
    expect(result.ruleVersion, 'title-v1');
    expect(f.requests.last.method, 'GET');
    expect(
      f.requests.last.path,
      '/ingestion/in%2Fbox/preview-attempts/$savedAttemptId/classification',
    );
    expect(f.requests.last.queryParameters, isEmpty);
    expect(f.requests.last.data, isNull);
    await expectLater(
      f.api.classification('id', 'bad/id'),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      f.requests.last.path,
      '/ingestion/id/preview-attempts/bad%2Fid/classification',
    );
  });
  test('11类及无标题/冲突/旧版未记录/不可用严格区分', () async {
    final f = AttemptProtocol();
    addTearDown(f.session.close);
    await f.login();
    for (final category in documentCategories.keys) {
      final row = savedRow();
      (row['classification'] as Map<String, Object?>)['category'] = category;
      f.response = row;
      expect(
        (await f.api.classification('id', savedAttemptId)).category,
        category,
      );
    }
    for (final reason in ['NO_TITLE', 'CONFLICTING_TITLES']) {
      final row = savedRow();
      (row['classification'] as Map<String, Object?>).addAll({
        'category': null,
        'reason': reason,
      });
      f.response = row;
      final result = await f.api.classification('id', savedAttemptId);
      expect(result.state, 'RECORDED');
      expect(result.category, isNull);
      expect(result.reason, reason);
    }
    for (final state in ['NOT_RECORDED', 'NOT_AVAILABLE']) {
      f.response = savedRow(state: state);
      final result = await f.api.classification('id', savedAttemptId);
      expect(result.state, state);
      expect(result.ruleVersion, isNull);
    }
  });
  test('拒绝错配尝试、未知状态/版本、缺字段、不一致类别原因和缺少人工确认', () async {
    final f = AttemptProtocol();
    addTearDown(f.session.close);
    await f.login();
    for (final change in [
      {'attemptId': '00000000-0000-4000-8000-000000000002'},
      {'state': 'UNKNOWN'},
      {'state': 'NOT_RECORDED'},
      {'classification': null},
      {'classification': []},
    ]) {
      f.response = {...savedRow(), ...change};
      await expectLater(
        f.api.classification('id', savedAttemptId),
        throwsA(isA<ApiFailure>()),
      );
    }
    f.response = savedRow()..remove('classification');
    await expectLater(
      f.api.classification('id', savedAttemptId),
      throwsA(isA<ApiFailure>()),
    );
    for (final change in [
      {'category': 'UNKNOWN'},
      {'category': null},
      {'reason': 'UNKNOWN'},
      {'reason': 'NO_TITLE'},
      {'requiresConfirmation': false},
      {'requiresConfirmation': null},
      {'ruleVersion': 'title-v2'},
      {'ruleVersion': null},
    ]) {
      final row = savedRow();
      (row['classification'] as Map<String, Object?>).addAll(change);
      f.response = row;
      await expectLater(
        f.api.classification('id', savedAttemptId),
        throwsA(isA<ApiFailure>()),
      );
    }
    final row = savedRow();
    (row['classification'] as Map<String, Object?>).remove('category');
    f.response = row;
    await expectLater(
      f.api.classification('id', savedAttemptId),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('错误不伪装缺失或自动重试，结束会话拒绝晚到分类', () async {
    final f = AttemptProtocol()..response = savedRow();
    addTearDown(f.session.close);
    await f.login();
    for (final status in [403, 429, 503]) {
      f.status = status;
      final count = f.requests.length;
      await expectLater(
        f.api.classification('id', savedAttemptId),
        throwsA(isA<ApiFailure>()),
      );
      expect(f.requests.length, count + 1);
    }
    f.status = 200;
    f.gate = Completer<void>();
    final pending = expectLater(
      f.api.classification('id', savedAttemptId),
      throwsA(isA<ApiFailure>()),
    );
    await Future<void>.delayed(Duration.zero);
    f.session.close();
    f.gate!.complete();
    await pending;
  });
  test('离线分类绑定本次实际提取，忽略后保留，不串材料或跨新实例', () async {
    final inbox = MemoryIngestion(),
        api = MemoryIngestionPreview(MemoryIngestion());
    await expectLater(
      api.classification('missing', 'x'),
      throwsA(isA<ApiFailure>()),
    );
    final memory = MemoryIngestionPreview(inbox),
        id = (await inbox.addFileExample()).id;
    final a = await memory.preview(id), b = await memory.preview(id);
    expect(a.attemptId, isNot(b.attemptId));
    await inbox.ignore(id);
    expect(
      (await memory.classification(id, a.attemptId)).category,
      'SERVICE_CONTRACT',
    );
    expect((await memory.attempts(id)).total, 2);
    final other = (await inbox.receive('另一份虚构文字材料')).id;
    await expectLater(
      memory.classification(other, a.attemptId),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      MemoryIngestionPreview(inbox).classification(id, a.attemptId),
      throwsA(isA<ApiFailure>()),
    );
  });
}
