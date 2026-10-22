import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruler_client/application/experience_provider.dart';
import 'package:ruler_client/domain/experience.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/domain/task_fields.dart';
import 'package:ruler_client/domain/today.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/experience_today.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'package:ruler_client/infrastructure/today_wire.dart';
import 'api_fixture.dart';
import 'today_fixture.dart';

void main() {
  test('北京时间跨日跨年与闰日倒计时不受设备时区影响', () {
    expect(shanghaiDate(DateTime.parse('2026-12-31T15:59:59Z')), '2026-12-31');
    expect(shanghaiDate(DateTime.parse('2026-12-31T16:00:00Z')), '2027-01-01');
    expect(
      shanghaiDate(DateTime.parse('2028-02-29T00:00:00+08:00')),
      '2028-02-29',
    );
    const task = TodayTask(
      id: '1',
      caseId: '1',
      title: '虚构',
      source: 'MANUAL',
      dueDate: '2028-03-01',
    );
    expect(task.timing('2028-02-28'), '剩余 2 天');
    expect(task.timing('2028-03-01'), '今日到期');
    expect(task.timing('2028-03-02'), '逾期 1 天');
  });
  test('三类来源保留服务端顺序，期间信息独立于普通编辑模型', () {
    final result = readToday(
      todayPage([
        confirmedTask(),
        {...todayTask(), 'source': 'AI_GENERATED', 'id': 'ai'},
        todayTask(1),
      ]),
      1,
    );
    expect(result.items.map((t) => t.id), ['deadline', 'ai', 'today-1']);
    expect(result.items.first.isDeadline, true);
    expect(result.items.first.baseDate, '2026-10-20');
    expect(result.items.first.dueDate, '2026-10-25');
    expect(result.items.last.description, '虚构任务说明');
    expect(result.date, '2026-10-22');
    expect(result.items.first.caseLabel, '(2026)虚构民初1号 · 虚构测试法院');
  });
  pageValidation();
  taskValidation();
  requestContract();
  offlineQuery();
  offlineCompletion();
}

void pageValidation() {
  test('错误日期时区分页总数、重复 ID 或截断数据整体拒绝', () {
    final valid = todayPage([todayTask()]);
    for (final patch in <Map<String, Object?>>[
      {'date': '2026-02-29'},
      {'date': '2026-10-22T00:00:00Z'},
      {'timeZone': 'UTC'},
      {'page': 2},
      {'page': 1.0},
      {'pageSize': 20.0},
      {'pageSize': 10},
      {'total': -1},
      {'total': 5001},
      {'total': 2},
      {'items': null},
      {
        'items': [todayTask(), todayTask()],
        'total': 2,
      },
    ]) {
      expect(
        () => readToday({...valid, ...patch}, 1),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(readToday(todayPage([], page: 2, total: 1), 2).items, isEmpty);
  });
}

void taskValidation() {
  test('拒绝未知来源、已完成、未来普通任务、坏日期和未确认期间', () {
    for (final patch in <Map<String, Object?>>[
      {'source': 'UNKNOWN'},
      {'status': 'DONE'},
      {'caseId': null},
      {'caseNo': null},
      {'court': null},
      {'title': ''},
      {'description': 5},
      {'dueDate': null},
      {'dueDate': '2026-10-23'},
      {'dueDate': '2026-02-30'},
      {'dueDate': '2026-10-22T08:00:00+08:00'},
    ]) {
      expect(
        () => readToday(
          todayPage([
            {...todayTask(), ...patch},
          ]),
          1,
        ),
        throwsA(isA<ApiFailure>()),
      );
    }
    for (final patch in <Map<String, Object?>>[
      {'deadlineConfirmedAt': null},
      {'deadlineConfirmedAt': '2026-02-30T00:00:00.000Z'},
      {'deadlineConfirmedById': ''},
      {'deadlineType': 12},
      {'baseDate': null},
    ]) {
      expect(
        () => readToday(
          todayPage([
            {...confirmedTask(), ...patch},
          ]),
          1,
        ),
        throwsA(isA<ApiFailure>()),
      );
    }
  });
}

void requestContract() {
  test('真实仓库查询只发分页，完成只 PATCH status 并编码路径', () async {
    final requests = <RequestOptions>[];
    final session = ApiSession(
      'http://127.0.0.1:3000',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((r) {
          requests.add(r);
          if (r.path == '/auth/login') return reply(tokens());
          if (r.method == 'PATCH') return reply({});
          return reply(todayPage([todayTask()], page: 2, total: 21));
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final repository = ApiRepository(session);
    expect((await repository.today(page: 2)).page, 2);
    expect(requests.last.path, '/tasks/today');
    expect(requests.last.queryParameters, {'page': 2, 'pageSize': 20});
    await repository.setTaskDone('fictional/id', true);
    expect(requests.last.path, '/tasks/fictional%2Fid');
    expect(requests.last.data, {'status': 'DONE'});
  });
}

void offlineQuery() {
  test('离线跨案件稳定排序分页，排除未来无日期与已完成，不改变原记录', () {
    final tasks = List.generate(
      21,
      (i) => ExperienceTask(id: '$i', title: '虚构$i', dueDate: '2026-10-22'),
    );
    final records = [
      ExperienceCase(
        id: 'first',
        caseNo: '虚构一',
        cause: '虚构',
        court: '虚构',
        tasks: tasks,
      ),
      ExperienceCase(
        id: 'second',
        caseNo: '虚构二',
        cause: '虚构',
        court: '虚构',
        tasks: const [
          ExperienceTask(id: 'overdue', title: '虚构逾期', dueDate: '2026-10-21'),
          ExperienceTask(id: 'future', title: '虚构未来', dueDate: '2026-10-23'),
          ExperienceTask(id: 'unset', title: '虚构无日期'),
          ExperienceTask(
            id: 'done',
            title: '虚构完成',
            dueDate: '2026-10-21',
            done: true,
          ),
        ],
      ),
    ];
    final now = DateTime.parse('2026-10-21T16:00:00Z');
    final page = experienceToday(records, now, 1);
    expect(page.total, 22);
    expect(page.hasNext, true);
    expect(page.items.first.caseId, 'second');
    expect(page.items.first.caseLabel, '虚构二');
    expect(experienceToday(records, now, 2).items.length, 2);
    expect(records.first.tasks.first.id, '0');
  });
}

void offlineCompletion() {
  test('Provider 完成幂等且保留资料，外案或删除后的任务不能修改', () async {
    final repository = MemoryExperience();
    final container = ProviderContainer(
      overrides: [experienceRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(experienceProvider.future);
    final controller = container.read(experienceProvider.notifier);
    final id = await controller.create('虚构一', '虚构', '虚构');
    await controller.addTask(id, '虚构任务');
    final task = (await repository.load()).single.tasks.single;
    await controller.updateTask(
      id,
      task.id,
      const TaskFields(
        title: '虚构任务',
        description: '虚构说明',
        dueDate: '2026-10-22',
      ),
    );
    await controller.completeTask(id, task.id);
    await controller.completeTask(id, task.id);
    final saved = container
        .read(experienceProvider)
        .requireValue
        .single
        .tasks
        .single;
    expect(saved.done, true);
    expect(saved.description, '虚构说明');
    final other = await controller.create('虚构二', '虚构', '虚构');
    await expectLater(
      controller.completeTask(other, task.id),
      throwsA(isA<ExperienceFailure>()),
    );
    await controller.remove(id);
    await expectLater(
      controller.completeTask(id, task.id),
      throwsA(isA<ExperienceFailure>()),
    );
  });
}
