import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/presentation/task_editor.dart';
import 'api_fixture.dart';
import 'online_evidence.dart';
import 'online_widget_test.dart' as online;
import 'experience_widget_test.dart' as demo;
import 'task_edit_fixture.dart';

const dateLabel = '工作日期（可空，YYYY-MM-DD）';
const descriptionLabel = '任务描述（可空）';
Future<void> fill(WidgetTester tester, String label, String value) async {
  final field = find.byKey(ValueKey(label));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester, TaskEditFixture fixture) async {
  await online.start(tester, fixture);
  await online.login(tester);
  await online.tap(tester, '(2026)虚构民初1号');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  editAndClear();
  creation();
  validationRetry();
  rereadFailure();
  expiredSession();
  pagination();
  pending();
  offline();
}

void editAndClear() {
  testWidgets('在线编辑标题/多行描述/闰日，保留完成状态；清空和取消语义', (tester) async {
    final fixture = TaskEditFixture()..seedTasks();
    await open(tester, fixture);
    await online.tap(tester, '编辑任务');
    expect(find.widgetWithText(TextFormField, '虚构原描述'), findsOneWidget);
    await fill(tester, '任务标题', '虚构修改任务');
    await fill(tester, descriptionLabel, '虚构第一行\n虚构第二行');
    await fill(tester, dateLabel, '2028-02-29');
    await captureOnline(tester, fileName: 'client-task-edit.png');
    await online.tap(tester, '保存任务修改');
    expect(find.text('已完成 · 2028-02-29'), findsOneWidget);
    expect(find.text('描述：虚构第一行\n虚构第二行'), findsOneWidget);
    await online.tap(tester, '恢复待办');
    expect(fixture.work.single['description'], '虚构第一行\n虚构第二行');
    await online.tap(tester, '编辑任务');
    await fill(tester, descriptionLabel, '虚构丢弃');
    await online.tap(tester, '取消');
    expect(find.text('描述：虚构第一行\n虚构第二行'), findsOneWidget);
    await online.tap(tester, '编辑任务');
    await fill(tester, descriptionLabel, ' ');
    await fill(tester, dateLabel, '');
    await online.tap(tester, '保存任务修改');
    expect(find.text('待办 · 未设工作日期'), findsOneWidget);
    expect(fixture.work.single['description'], isNull);
    expect(fixture.work.single['dueDate'], isNull);
  });
}

void creation() {
  testWidgets('在线新建可一次填写描述日期，不补写；取消新建不请求', (tester) async {
    final fixture = TaskEditFixture()..seed();
    await open(tester, fixture);
    await online.tap(tester, '新增工作任务');
    await fill(tester, '任务标题', '虚构新任务');
    await fill(tester, descriptionLabel, '虚构新描述');
    await fill(tester, dateLabel, '2028-02-29');
    await online.tap(tester, '保存到测试服务');
    expect(fixture.work.single['description'], '虚构新描述');
    expect(fixture.requests.where((r) => r.startsWith('PATCH')), isEmpty);
    await online.tap(tester, '新增工作任务');
    await fill(tester, '任务标题', '虚构取消新建');
    await online.tap(tester, '取消');
    expect(fixture.work.length, 1);
  });
}

void validationRetry() {
  testWidgets('非法日期包含长时间串不能截短提交；写失败保留三字段并直接重试', (tester) async {
    final fixture = TaskEditFixture()..seedTasks();
    await open(tester, fixture);
    await online.tap(tester, '编辑任务');
    await fill(tester, dateLabel, '2028-02-29T00:00:00Z');
    await online.tap(tester, '保存任务修改');
    expect(find.text('请输入有效工作日期'), findsOneWidget);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')), isEmpty);
    await fill(tester, dateLabel, '2028-02-29');
    await fill(tester, descriptionLabel, '虚构重试描述');
    fixture.failWrite = true;
    await online.tap(tester, '保存任务修改');
    expect(find.textContaining('记录重复'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '虚构重试描述'), findsOneWidget);
    fixture.failWrite = false;
    await online.tap(tester, '保存任务修改');
    expect(fixture.work.single['description'], '虚构重试描述');
    expect(fixture.work.single['dueDate'], '2028-02-29');
    expect(fixture.work.single['status'], 'DONE');
  });
}

void rereadFailure() {
  testWidgets('编辑成功但重读失败只重新 GET，旧列表不显示且不重复 PATCH', (tester) async {
    final fixture = TaskEditFixture()..seedTasks();
    await open(tester, fixture);
    await online.tap(tester, '编辑任务');
    await fill(tester, '任务标题', '虚构已经保存');
    fixture.failReadAfterWrite = true;
    await online.tap(tester, '保存任务修改');
    expect(find.byType(TaskEditor), findsNothing);
    expect(find.text('虚构任务0'), findsNothing);
    await online.tap(tester, '重新加载');
    expect(find.text('虚构已经保存'), findsOneWidget);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')).length, 1);
  });
}

void expiredSession() {
  testWidgets('编辑时会话失效清除任务页面和描述草稿', (tester) async {
    final fixture = TaskEditFixture()..seedTasks();
    await open(tester, fixture);
    await online.tap(tester, '编辑任务');
    await fill(tester, descriptionLabel, '虚构尚未保存');
    fixture.expire = true;
    await online.tap(tester, '保存任务修改');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(TaskEditor), findsNothing);
    expect(find.textContaining('虚构尚未保存'), findsNothing);
  });
}

void pagination() {
  testWidgets('第二页编辑后保留页码，改日期按服务端排序移动到第一页', (tester) async {
    final fixture = TaskEditFixture()..seedTasks(21);
    await open(tester, fixture);
    await online.tap(tester, '下一页');
    expect(find.text('虚构任务20'), findsOneWidget);
    await online.tap(tester, '编辑任务');
    await fill(tester, dateLabel, '2028-02-29');
    await online.tap(tester, '保存任务修改');
    expect(find.text('第 2 页 · 共 21 条'), findsOneWidget);
    expect(find.text('虚构任务20'), findsNothing);
    expect(find.text('虚构任务19'), findsOneWidget);
    await online.tap(tester, '上一页');
    expect(find.text('虚构任务20'), findsOneWidget);
  });
}

class SlowTaskFixture extends TaskEditFixture {
  final gate = Completer<void>();
  @override
  Dio dio() => Dio()
    ..httpClientAdapter = TestAdapter((request) async {
      if (request.method == 'PATCH') await gate.future;
      return handle(request);
    });
}

void pending() {
  testWidgets('真实导航内保存期间禁用表单与返回，结束后只提交一次', (tester) async {
    final fixture = SlowTaskFixture()..seedTasks();
    await open(tester, fixture);
    await online.tap(tester, '编辑任务');
    await tester.tap(find.text('保存任务修改'));
    await tester.pump();
    expect(
      tester.widget<TextFormField>(find.byKey(const ValueKey('任务标题'))).enabled,
      false,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存中…'))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditor), findsOneWidget);
    fixture.gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditor), findsNothing);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')).length, 1);
  });
}

void offline() {
  testWidgets('窄屏深色离线任务编辑与完成恢复，返回重进保留，清空日期描述', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await demo.enter(tester);
    await demo.createCase(tester);
    await online.tap(tester, '工作任务');
    await online.tap(tester, '添加体验任务');
    await online.tap(tester, '编辑任务');
    await fill(tester, '任务标题', '虚构编辑任务');
    await fill(tester, descriptionLabel, '虚构待办说明');
    await fill(tester, dateLabel, '2028-02-29');
    await online.tap(tester, '保存体验修改');
    await online.tap(tester, '标记完成');
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('2028-02-29'), findsOneWidget);
    await captureOnline(
      tester,
      fileName: 'client-task-edit-demo.png',
      key: demo.captureKey,
    );
    await online.tap(tester, '案件信息');
    await online.tap(tester, '工作任务');
    await online.tap(tester, '恢复待办');
    expect(find.text('描述：虚构待办说明'), findsOneWidget);
    await online.tap(tester, '编辑任务');
    await fill(tester, descriptionLabel, '');
    await fill(tester, dateLabel, '');
    await online.tap(tester, '保存体验修改');
    expect(find.text('未设工作日期'), findsOneWidget);
    expect(find.text('描述：未填写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
