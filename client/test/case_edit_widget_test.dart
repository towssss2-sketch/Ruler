import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/case_fields.dart';
import 'package:ruler_client/presentation/case_edit_dialog.dart';
import 'online_evidence.dart';
import 'online_fixture.dart';
import 'online_widget_test.dart' as online;
import 'experience_widget_test.dart' as demo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  onlineEdit();
  failedAndCancelledEdit();
  offlineEdit();
  pendingEdit();
  expiredEdit();
  invalidEdit();
}

Future<void> choose(WidgetTester tester, String field, String value) async {
  await tester.ensureVisible(find.byKey(ValueKey(field)));
  await tester.tap(find.byKey(ValueKey(field)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void onlineEdit() {
  testWidgets('在线编辑回填、修改阶段和结案；详情与返回列表同步', (tester) async {
    final server = OnlineFixture()..seed();
    await online.start(tester, server);
    await online.login(tester);
    await online.tap(tester, '(2026)虚构民初1号');
    await online.tap(tester, '编辑案件信息');
    expect(find.widgetWithText(TextFormField, '虚构合同纠纷'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '（2026）虚构民终2号');
    await tester.enterText(find.byType(TextFormField).at(1), '虚构买卖纠纷');
    await choose(tester, '审理阶段', '二审');
    await choose(tester, '案件状态', '已结案');
    await captureOnline(tester, fileName: 'client-case-edit.png');
    await online.tap(tester, '保存到测试服务');
    expect(find.text('(2026)虚构民终2号'), findsOneWidget);
    expect(find.textContaining('二审 · 已结案'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('虚构买卖纠纷'), findsOneWidget);
    expect(find.textContaining('二审 · 已结案'), findsOneWidget);
    expect(server.requests.where((r) => r == 'PATCH /cases/case-1').length, 1);
  });
}

void failedAndCancelledEdit() {
  testWidgets('保存冲突保留输入，取消不更新，重试成功后才能显示新信息', (tester) async {
    final server = OnlineFixture()..seed();
    await online.start(tester, server);
    await online.login(tester);
    await online.tap(tester, '(2026)虚构民初1号');
    await online.tap(tester, '编辑案件信息');
    await tester.enterText(find.byType(TextFormField).at(1), '虚构修改');
    server.failWrite = true;
    await online.tap(tester, '保存到测试服务');
    expect(find.textContaining('记录重复'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '虚构修改'), findsOneWidget);
    expect(server.records.single['cause'], '虚构合同纠纷');
    server.failWrite = false;
    await online.tap(tester, '保存到测试服务');
    expect(find.textContaining('虚构修改 ·'), findsOneWidget);
    await online.tap(tester, '编辑案件信息');
    await tester.enterText(find.byType(TextFormField).at(1), '虚构取消');
    await online.tap(tester, '取消');
    expect(server.records.single['cause'], '虚构修改');
    expect(find.textContaining('虚构取消'), findsNothing);
  });
}

void offlineEdit() {
  testWidgets('窄屏离线编辑可结案再恢复；文件与任务保持，返回列表更新', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await demo.enter(tester);
    await demo.createCase(tester);
    await online.tap(tester, '示例文件');
    await online.tap(tester, '添加示例文件版本');
    await online.tap(tester, '工作任务');
    await online.tap(tester, '添加体验任务');
    await online.tap(tester, '案件信息');
    await online.tap(tester, '编辑案件信息');
    await tester.enterText(find.byType(TextFormField).at(1), '虚构修改后的案由');
    await choose(tester, '审理阶段', '执行');
    await choose(tester, '案件状态', '已结案');
    await online.tap(tester, '保存体验修改');
    expect(find.text('执行 · 已结案'), findsOneWidget);
    expect(find.text('1 个示例版本\n1 项待办'), findsOneWidget);
    await online.tap(tester, '编辑案件信息');
    await choose(tester, '案件状态', '进行中');
    await online.tap(tester, '保存体验修改');
    expect(find.text('执行 · 进行中'), findsOneWidget);
    await captureOnline(
      tester,
      fileName: 'client-case-edit-demo.png',
      key: demo.captureKey,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('虚构修改后的案由'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void pendingEdit() {
  testWidgets('保存未完成禁止连点、取消和系统返回；完成后才关闭', (tester) async {
    final gate = Completer<void>();
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => CaseEditDialog(
                  initial: const CaseFields(
                    caseNo: '(2026)虚构民初1号',
                    cause: '虚构',
                    court: '虚构',
                  ),
                  save: (_) {
                    writes++;
                    return gate.future;
                  },
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await online.tap(tester, '打开');
    await tester.tap(find.text('保存到测试服务'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CaseEditDialog), findsOneWidget);
    expect(writes, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CaseEditDialog), findsNothing);
  });
}

void expiredEdit() {
  testWidgets('编辑中会话失效销毁表单，不把输入带入下一账号', (tester) async {
    final server = OnlineFixture()..seed();
    await online.start(tester, server);
    await online.login(tester);
    await online.tap(tester, '(2026)虚构民初1号');
    await online.tap(tester, '编辑案件信息');
    await tester.enterText(find.byType(TextFormField).at(1), '虚构未保存内容');
    server.expire = true;
    await online.tap(tester, '保存到测试服务');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(CaseEditDialog), findsNothing);
    expect(find.text('虚构未保存内容'), findsNothing);
    expect(server.records.single['cause'], '虚构合同纠纷');
  });
}

void invalidEdit() {
  testWidgets('不完整案号和空案由拒绝提交；取消后原案件不变', (tester) async {
    final server = OnlineFixture()..seed();
    await online.start(tester, server);
    await online.login(tester);
    await online.tap(tester, '(2026)虚构民初1号');
    await online.tap(tester, '编辑案件信息');
    await tester.enterText(find.byType(TextFormField).first, '随便写');
    await tester.enterText(find.byType(TextFormField).at(1), ' ');
    await online.tap(tester, '保存到测试服务');
    expect(find.textContaining('请输入完整案号'), findsOneWidget);
    expect(find.text('请填写案由'), findsOneWidget);
    expect(server.requests.where((r) => r.startsWith('PATCH')), isEmpty);
    await online.tap(tester, '取消');
    expect(server.records.single['caseNo'], '(2026)虚构民初1号');
  });
}
