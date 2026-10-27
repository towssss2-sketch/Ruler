import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/domain/ingestion_preview.dart';
import 'package:ruler_client/infrastructure/memory_ingestion.dart';
import 'package:ruler_client/infrastructure/memory_ingestion_preview.dart';
import 'preview_attempt_fixture.dart';

void main() {
  test('提取历史只发GET，编码路径且有界分页，拒绝非法页码，不启动提取', () async {
    final f = AttemptProtocol();
    addTearDown(f.session.close);
    await f.login();
    final page = await f.api.attempts('in/box');
    expect(f.requests.last.method, 'GET');
    expect(f.requests.last.path, '/ingestion/in%2Fbox/preview-attempts');
    expect(f.requests.last.queryParameters, {'page': 1, 'pageSize': 20});
    expect(page.items.single.status, 'SUCCEEDED');
    expect(() => page.items.clear(), throwsUnsupportedError);
    final count = f.requests.length;
    for (final value in [0, -1, 10000]) {
      await expectLater(
        f.api.attempts('id', page: value),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(f.requests.length, count);
    f.response = {'items': [], 'total': 1, 'page': 2, 'pageSize': 20};
    expect((await f.api.attempts('id', page: 2)).items, isEmpty);
  });
  test('全部状态和固定原因严格解析，时间与失败可重试语义一致', () async {
    final f = AttemptProtocol();
    addTearDown(f.session.close);
    await f.login();
    for (final status in ['RUNNING', 'SUCCEEDED', 'INTERRUPTED']) {
      f.response = attemptPage([attemptRow(status: status)]);
      expect((await f.api.attempts('id')).items.single.status, status);
    }
    for (final reason in previewReasons.keys) {
      f.response = attemptPage([
        attemptRow(status: 'MANUAL_REQUIRED', reason: reason),
      ]);
      final result = (await f.api.attempts('id')).items.single;
      expect(result.reason, reason);
      expect(result.retryable, ['TIMEOUT', 'UNAVAILABLE'].contains(reason));
    }
  });
  test('坏分页、重复身份、未知状态、缺字段及非法日期拒绝，不当作空历史', () async {
    final f = AttemptProtocol();
    addTearDown(f.session.close);
    await f.login();
    for (final change in [
      {'page': 2},
      {'pageSize': 100},
      {'total': -1},
      {'total': '1'},
      {'total': 2},
      {'items': null},
      {
        'items': [attemptRow(), attemptRow()],
        'total': 2,
      },
    ]) {
      f.response = {...attemptPage(), ...change};
      await expectLater(f.api.attempts('id'), throwsA(isA<ApiFailure>()));
    }
    for (final change in [
      {'id': 'bad'},
      {'status': 'unknown'},
      {'reason': 'TIMEOUT'},
      {'status': 'MANUAL_REQUIRED'},
      {'finishedAt': null},
      {'status': 'RUNNING'},
      {'retryable': true},
      {'retryable': null},
      {'startedAt': '2026-02-30T00:00:00.000Z'},
      {'finishedAt': '2026-10-26T00:00:00.000Z'},
      {'startedAt': 'not-a-date'},
      {'startedAt': null},
    ]) {
      f.response = attemptPage([
        {...attemptRow(), ...change},
      ]);
      await expectLater(f.api.attempts('id'), throwsA(isA<ApiFailure>()));
    }
    for (final key in ['reason', 'finishedAt']) {
      final row = attemptRow()..remove(key);
      f.response = attemptPage([row]);
      await expectLater(f.api.attempts('id'), throwsA(isA<ApiFailure>()));
    }
  });
  test('读取错误不重复请求，退出会话后拒绝晚到记录', () async {
    final f = AttemptProtocol();
    addTearDown(f.session.close);
    await f.login();
    for (final status in [403, 429, 503]) {
      f.status = status;
      final count = f.requests.length;
      await expectLater(f.api.attempts('id'), throwsA(isA<ApiFailure>()));
      expect(f.requests.length, count + 1);
    }
    f.status = 200;
    f.gate = Completer<void>();
    final pending = expectLater(
      f.api.attempts('id'),
      throwsA(isA<ApiFailure>()),
    );
    await Future<void>.delayed(Duration.zero);
    f.session.close();
    f.gate!.complete();
    await pending;
  });
  test('离线仅保存实际点击的虚构记录，分页/忽略保留，读取不产生新尝试且不跨新实例', () async {
    final inbox = MemoryIngestion(),
        api = MemoryIngestionPreview(MemoryIngestion());
    await expectLater(api.attempts('missing'), throwsA(isA<ApiFailure>()));
    final memory = MemoryIngestionPreview(inbox),
        id = (await inbox.addFileExample()).id;
    expect((await memory.attempts(id)).total, 0);
    for (var i = 0; i < 21; i++) {
      await memory.preview(id);
    }
    expect((await memory.attempts(id)).items.length, 20);
    expect(
      (await memory.attempts(id, page: 2)).items.single.id,
      'demo-preview-1',
    );
    await inbox.ignore(id);
    expect((await memory.attempts(id)).total, 21);
    expect((await MemoryIngestionPreview(inbox).attempts(id)).total, 0);
    await expectLater(memory.attempts(id, page: 0), throwsA(isA<ApiFailure>()));
    final text = await inbox.receive('虚构文字');
    await expectLater(memory.attempts(text.id), throwsA(isA<ApiFailure>()));
  });
}
