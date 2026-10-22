import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/experience_provider.dart';
import 'package:ruler_client/domain/task_fields.dart';
import 'package:ruler_client/domain/today.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'package:ruler_client/presentation/today_calendar.dart';
import 'package:ruler_client/presentation/today_page.dart';
import 'online_evidence.dart';
import 'online_widget_test.dart' as online;
import 'today_fixture.dart';

Future<void> open(WidgetTester tester, TodayFixture fixture) async {
  await online.start(tester, fixture);
  await online.login(tester);
  await tester.tap(find.byTooltip('今日任务'));
  await tester.pumpAndSettle();
}

Future<void> action(WidgetTester tester, String id, String label) async {
  final button = find.descendant(
    of: find.byKey(ValueKey(id)),
    matching: find.text(label),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  sourcesAndConfirmation();
  recovery();
  pagination();
  session();
  pending();
  caseNavigation();
  offline();
  calendar();
  lifecycle();
}

void sourcesAndConfirmation() {
  testWidgets('三种任务来源与期间确认，取消不写，确认只改完成状态', (tester) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = TodayFixture()..seedToday();
    fixture.work.insert(0, confirmedTask());
    fixture.work.insert(1, {
      ...todayTask(2),
      'source': 'AI_GENERATED',
      'dueDate': '2026-10-21',
    });
    await open(tester, fixture);
    expect(find.text('法定期间 · 已确认记录'), findsOneWidget);
    expect(find.text('AI 建议任务'), findsOneWidget);
    expect(find.text('剩余 3 天 · 2026-10-25'), findsOneWidget);
    expect(find.text('编辑任务'), findsNothing);
    expect(find.text('删除任务'), findsNothing);
    await captureOnline(tester, fileName: 'client-today.png');
    await action(tester, 'deadline', '标记完成');
    await online.tap(tester, '取消');
    expect(fixture.requests.where((r) => r.startsWith('PATCH')), isEmpty);
    await action(tester, 'deadline', '标记完成');
    await online.tap(tester, '确认标记完成');
    expect(find.text('虚构已确认期间'), findsNothing);
    expect(fixture.work.first['status'], 'DONE');
    expect(fixture.work.first['dueDate'], '2026-10-25T00:00:00.000Z');
  });
}

void recovery() {
  testWidgets('读失败隐藏旧列表，写失败保留；写成功后读失败仅重读', (tester) async {
    final fixture = TodayFixture()..seedToday();
    await open(tester, fixture);
    fixture.failRead = true;
    await tester.tap(find.byTooltip('刷新今日清单'));
    await tester.pumpAndSettle();
    expect(find.text('虚构今日任务0'), findsNothing);
    fixture.failRead = false;
    await online.tap(tester, '重新加载');
    fixture.failWrite = true;
    await action(tester, 'today-0', '标记完成');
    expect(find.textContaining('记录重复'), findsOneWidget);
    expect(fixture.work.single['status'], 'TODO');
    fixture.failWrite = false;
    fixture.failAfterWrite = true;
    await action(tester, 'today-0', '标记完成');
    expect(find.text('虚构今日任务0'), findsNothing);
    fixture.failRead = false;
    await online.tap(tester, '重新加载');
    expect(find.text('暂无需要今日处理的任务'), findsOneWidget);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')).length, 2);
  });
}

void pagination() {
  testWidgets('跨页完成末项回第一页，保留服务端总数，日历不伪造任务统计', (tester) async {
    final fixture = TodayFixture()..seedToday(21);
    await open(tester, fixture);
    await online.tap(tester, '下一页');
    expect(find.text('第 2 页 · 共 21 条'), findsOneWidget);
    await action(tester, 'today-20', '标记完成');
    await tester.scrollUntilVisible(find.text('第 1 页 · 共 20 条'), 600);
    expect(find.text('第 1 页 · 共 20 条'), findsOneWidget);
    expect(fixture.work.last['status'], 'DONE');
  });
}

void session() {
  testWidgets('会话失效销毁汇总页面，不能返回旧任务', (tester) async {
    final fixture = TodayFixture()..seedToday();
    await open(tester, fixture);
    fixture.expire = true;
    await tester.tap(find.byTooltip('刷新今日清单'));
    await tester.pumpAndSettle();
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(TodayPage), findsNothing);
    expect(find.text('虚构今日任务0'), findsNothing);
  });
}

void pending() {
  testWidgets('完成写入期间禁止返回和重复操作，成功后仅一次提交', (tester) async {
    final fixture = TodayFixture()..seedToday();
    fixture.writeGate = Completer<void>();
    await open(tester, fixture);
    await tester.tap(find.text('标记完成'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(TodayPage), findsOneWidget);
    await tester.tap(find.text('处理中…'), warnIfMissed: false);
    fixture.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('暂无需要今日处理的任务'), findsOneWidget);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')).length, 1);
  });
}

void caseNavigation() {
  testWidgets('打开所属案件实时读取详情，返回后刷新汇总', (tester) async {
    final fixture = TodayFixture()..seedToday();
    fixture.records.add({
      ...fixture.records.first,
      'id': 'case-2',
      'caseNo': '(2026)虚构民初2号',
    });
    fixture.work.single.addAll({'caseId': 'case-2', 'caseNo': '(2026)虚构民初2号'});
    await open(tester, fixture);
    await action(tester, 'today-0', '打开所属案件');
    expect(find.text('(2026)虚构民初2号'), findsOneWidget);
    expect(fixture.requests, contains('GET /cases/case-2'));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('今日任务汇总'), findsOneWidget);
    expect(fixture.requests.where((r) => r == 'GET /tasks/today').length, 2);
  });
}

void offline() {
  testWidgets('窄屏深色离线汇总、案件往返与完成，实际内存数据一致', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final repository = MemoryExperience();
    final id = await repository.create('(2026)虚构民初1号', '虚构合同纠纷', '虚构法院');
    await repository.addTask(id, '虚构今日核对');
    final taskId = (await repository.load()).single.tasks.single.id;
    await repository.updateTask(
      id,
      taskId,
      TaskFields(title: '虚构今日核对', dueDate: shanghaiDate(DateTime.now())),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [experienceRepositoryProvider.overrideWithValue(repository)],
        child: const RepaintBoundary(key: onlineCaptureKey, child: RulerApp()),
      ),
    );
    await tester.pumpAndSettle();
    await online.tap(tester, '开始虚构体验');
    await tester.tap(find.byTooltip('今日任务'));
    await tester.pumpAndSettle();
    await captureOnline(tester, fileName: 'client-today-demo.png');
    await action(tester, taskId, '打开所属案件');
    expect(find.text('体验案件详情'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('今日任务汇总'), findsOneWidget);
    await action(tester, taskId, '标记完成');
    expect(find.text('暂无需要今日处理的任务'), findsOneWidget);
    expect((await repository.load()).single.tasks.single.done, true);
    expect(tester.takeException(), isNull);
  });
}

void calendar() {
  testWidgets('迷你日历显示闰年二月，展开可滚动且标记汇总日期', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: const [TodayCalendar(date: '2028-02-29')]),
        ),
      ),
    );
    await online.tap(tester, '2028 年 2 月 · 查看日历');
    expect(find.text('29'), findsOneWidget);
    expect(find.text('30'), findsNothing);
    expect(find.textContaining('仅标记汇总日期'), findsOneWidget);
  });
}

void lifecycle() {
  testWidgets('加载中有进度，恢复应用重读服务端日期而非设备日期', (tester) async {
    final pending = Completer<TodaySnapshot>();
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(
          load: (_) => ++reads == 1
              ? pending.future
              : Future.value(TodaySnapshot([], 0, 1, '2027-01-01')),
          complete: (_) async {},
          openCase: (_) async {},
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(TodaySnapshot([], 0, 1, '2026-12-31'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('2027-01-01'), findsOneWidget);
    expect(reads, 2);
  });
}
