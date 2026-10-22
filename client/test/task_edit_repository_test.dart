import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/domain/task_fields.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'package:ruler_client/infrastructure/task_wire.dart';
import 'api_fixture.dart';

Map<String, Object?> taskRow() => {
  'id': 'task-1',
  'title': '虚构任务',
  'description': '虚构描述',
  'dueDate': '2028-02-29T00:00:00.000Z',
  'status': 'DONE',
  'source': 'MANUAL',
};

void main() {
  dates();
  fields();
  wire();
  requests();
  memory();
}

void dates() {
  test('工作日期严格日历校验，闰年/世纪/边界，不接受时间或时区', () {
    for (final date in [
      '2028-02-29',
      '2000-02-29',
      '1000-01-01',
      '9999-12-31',
    ]) {
      expect(validWorkDate(date), true);
    }
    for (final date in [
      '2026-02-29',
      '1900-02-29',
      '2026-04-31',
      '2026-00-01',
      '2026-01-00',
      '2026-13-01',
      '0001-01-01',
      '10000-01-01',
      '2026-1-1',
      '2026-01-01T00:00:00Z',
      '2026-01-01+08:00',
    ]) {
      expect(validWorkDate(date), false);
    }
  });
}

void fields() {
  test('标题/描述 Unicode 长度边界、首尾空白与 null 清空', () {
    expect(
      TaskFields(title: '𠀀' * 255, description: '文' * 10000).error,
      isNull,
    );
    for (final item in [
      const TaskFields(title: ' '),
      TaskFields(title: '𠀀' * 256),
      TaskFields(title: '虚构', description: '文' * 10001),
    ]) {
      expect(item.error, isNotNull);
    }
    expect(
      const TaskFields(
        title: ' 虚构 ',
        description: ' 一\n二 ',
        dueDate: ' 2028-02-29 ',
      ).normalized.toJson(),
      {'title': '虚构', 'description': '一\n二', 'dueDate': '2028-02-29'},
    );
    expect(
      const TaskFields(
        title: '虚构',
        description: ' ',
        dueDate: ' ',
      ).normalized.toJson(),
      {'title': '虚构', 'description': null, 'dueDate': null},
    );
  });
}

void wire() {
  test('读取完整手动任务，拒绝非手动来源、损坏资料和非午夜 UTC 日期', () {
    final parsed = readManualTask(taskRow());
    expect(parsed.done, true);
    expect(parsed.fields.description, '虚构描述');
    expect(parsed.fields.dueDate, '2028-02-29');
    for (final patch in <Map<String, Object?>>[
      {'source': 'DEADLINE_RULE'},
      {'source': 'AI_GENERATED'},
      {'source': null},
      {'status': 'UNKNOWN'},
      {'description': 42},
      {'description': '文' * 10001},
      {'title': ''},
      {'dueDate': 42},
      {'dueDate': '2026-02-30'},
      {'dueDate': '2028-02-29T12:00:00.000Z'},
      {'dueDate': '2028-02-29T08:00:00+08:00'},
    ]) {
      expect(
        () => readManualTask({...taskRow(), ...patch}),
        throwsA(
          isA<ApiFailure>().having((e) => e.message, 'safe', '服务响应格式异常。'),
        ),
      );
    }
    expect(
      readManualTask({
        ...taskRow(),
        'dueDate': null,
        'description': null,
      }).description,
      isNull,
    );
  });
}

void requests() {
  test('创建/编辑三字段协议和 null；修改不发送完成状态/来源，非法输入无请求', () async {
    final received = <RequestOptions>[];
    final session = requestSession(received);
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final repository = ApiRepository(session);
    final page = await repository.tasks('case-1', page: 2);
    expect(page.items.single.description, '虚构描述');
    expect(received.single.queryParameters, {
      'source': 'MANUAL',
      'page': 2,
      'pageSize': 20,
    });
    await repository.addTask(
      'case-1',
      ' 虚构新增 ',
      '2028-02-29',
      description: ' 虚构描述 ',
    );
    expect(received.last.method, 'POST');
    expect(received.last.data, {
      'title': '虚构新增',
      'description': '虚构描述',
      'dueDate': '2028-02-29',
    });
    await repository.updateTask(
      'one/two',
      const TaskFields(title: '虚构修改', description: ' ', dueDate: ''),
    );
    expect(received.last.method, 'PATCH');
    expect(received.last.path, '/tasks/one%2Ftwo');
    expect(received.last.data, {
      'title': '虚构修改',
      'description': null,
      'dueDate': null,
    });
    await expectLater(
      repository.updateTask(
        'one',
        const TaskFields(title: '虚构', dueDate: '2026-02-30'),
      ),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      repository.addTask('case', ' ', null),
      throwsA(isA<ApiFailure>()),
    );
    expect(received.length, 3);
  });
}

void memory() {
  test('离线任务编辑保留身份/完成状态/关联数据；切换保留描述日期，清空及外案拒绝', () async {
    final repository = MemoryExperience();
    final id = await repository.create('虚构案甲', '虚构案由', '虚构法院');
    final other = await repository.create('虚构案乙', '虚构案由', '虚构法院');
    await repository.addTask(id, '虚构任务甲');
    await repository.addTask(id, '虚构任务乙');
    await repository.addSample(id);
    final before = (await repository.load()).last;
    final task = before.tasks.first;
    await repository.toggleTask(id, task.id);
    await repository.updateTask(
      id,
      task.id,
      const TaskFields(
        title: '虚构修改',
        description: ' 虚构描述 ',
        dueDate: '2028-02-29',
      ),
    );
    final after = (await repository.load()).last;
    expect(after.tasks.first.done, true);
    expect(after.tasks.first.id, task.id);
    expect(after.tasks.first.description, '虚构描述');
    expect(after.tasks.last, same(before.tasks.last));
    expect(after.updatedAt, before.updatedAt);
    expect(after.files.single.id, before.files.single.id);
    await expectLater(
      repository.updateTask(other, task.id, task.fields),
      throwsException,
    );
    await expectLater(
      repository.updateTask(
        id,
        task.id,
        const TaskFields(title: ' ', dueDate: '2026-02-30'),
      ),
      throwsException,
    );
    expect((await repository.load()).last, same(after));
    await repository.toggleTask(id, task.id);
    final toggled = (await repository.load()).last.tasks.first;
    expect(toggled.done, false);
    expect(toggled.description, '虚构描述');
    expect(toggled.dueDate, '2028-02-29');
    await repository.updateTask(id, task.id, const TaskFields(title: '虚构清空'));
    expect((await repository.load()).last.tasks.first.fields.toJson(), {
      'title': '虚构清空',
      'description': null,
      'dueDate': null,
    });
    expect((await repository.load()).first.tasks, isEmpty);
    await repository.remove(id);
    await expectLater(
      repository.updateTask(id, task.id, task.fields),
      throwsException,
    );
  });
}

ApiSession requestSession(List<RequestOptions> received) => ApiSession(
  'https://example.invalid',
  dio: Dio()
    ..httpClientAdapter = TestAdapter((r) {
      if (r.path == '/auth/login') return reply(tokens());
      received.add(r);
      return reply(
        r.method == 'GET'
            ? {
                'items': [taskRow()],
                'page': 2,
                'total': 21,
              }
            : {'id': 'task-1'},
      );
    }),
);
