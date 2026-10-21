import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/case_supplement.dart';
import 'package:ruler_client/presentation/case_supplement_editor.dart';
import 'online_evidence.dart';
import 'online_fixture.dart';
import 'online_widget_test.dart' as online;
import 'party_widget_test.dart' show openDetail, ReadFailureFixture;
import 'experience_widget_test.dart' as demo;

Future<void> fill(WidgetTester tester, String label, String value) async {
  final field = find.byKey(ValueKey(label));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> status(WidgetTester tester, String value) async {
  final choice = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  onlineSave();
  validationAndRetry();
  readFailure();
  sessionFailure();
  pendingSave();
  offlineExperience();
}

void onlineSave() {
  testWidgets('在线编辑六项资料，准确金额、状态、清空和刷新保留名单', (tester) async {
    final fixture = OnlineFixture()..seed();
    fixture.records.single.addAll({'judge': '虚构原审判员', 'fee': '12.34'});
    await openDetail(tester, fixture);
    await online.tap(tester, '编辑其他案件信息');
    expect(find.widgetWithText(TextField, '虚构原审判员'), findsOneWidget);
    await fill(tester, '审判员', '虚构新审判员');
    await fill(tester, '书记员', '虚构书记员');
    await fill(tester, '书记员电话', '虚构电话');
    await fill(tester, '费用金额（元）', '999999999999.9');
    await status(tester, '部分已付');
    await fill(tester, '备注', '虚构首行\n虚构次行');
    await captureOnline(tester, fileName: 'client-case-supplement-editor.png');
    await online.tap(tester, '保存案件资料');
    expect(find.text('费用（元）：999999999999.90 · 部分已付'), findsOneWidget);
    expect(find.text('备注：虚构首行\n虚构次行'), findsOneWidget);
    expect((fixture.records.single['parties'] as List).single['id'], 'party-1');
    await online.tap(tester, '编辑其他案件信息');
    await fill(tester, '书记员电话', ' ');
    await fill(tester, '费用金额（元）', '');
    await fill(tester, '备注', '');
    await status(tester, '免收');
    await online.tap(tester, '保存案件资料');
    expect(find.text('费用（元）：未填写 · 免收'), findsOneWidget);
    expect(fixture.records.single['clerkPhone'], isNull);
    expect(fixture.records.single['notes'], isNull);
    expect(fixture.records.single['judge'], '虚构新审判员');
  });
}

void validationAndRetry() {
  testWidgets('非法金额不提交，失败保留草稿可直接重试；取消不修改', (tester) async {
    final fixture = OnlineFixture()..seed();
    await openDetail(tester, fixture);
    await online.tap(tester, '编辑其他案件信息');
    await fill(tester, '费用金额（元）', '1.001');
    await online.tap(tester, '保存案件资料');
    expect(find.textContaining('费用请输入非负金额'), findsOneWidget);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')), isEmpty);
    await fill(tester, '费用金额（元）', '0');
    await fill(tester, '备注', '虚构保留草稿');
    fixture.failWrite = true;
    await online.tap(tester, '保存案件资料');
    expect(find.widgetWithText(TextField, '虚构保留草稿'), findsOneWidget);
    expect(find.textContaining('记录重复'), findsOneWidget);
    fixture.failWrite = false;
    await online.tap(tester, '保存案件资料');
    expect(find.text('费用（元）：0.00 · 未付'), findsOneWidget);
    await online.tap(tester, '编辑其他案件信息');
    await fill(tester, '备注', '虚构取消内容');
    await online.tap(tester, '取消编辑');
    expect(find.text('备注：虚构保留草稿'), findsOneWidget);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')).length, 2);
  });
}

void readFailure() {
  testWidgets('资料保存后重读失败只重试 GET，不重复保存或显示陈旧详情', (tester) async {
    final fixture = ReadFailureFixture()..seed();
    await openDetail(tester, fixture);
    await online.tap(tester, '编辑其他案件信息');
    await fill(tester, '备注', '虚构已保存备注');
    await online.tap(tester, '保存案件资料');
    expect(find.byType(CaseSupplementEditor), findsNothing);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('备注：虚构已保存备注'), findsNothing);
    await online.tap(tester, '重新加载');
    expect(find.text('备注：虚构已保存备注'), findsOneWidget);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')).length, 1);
  });
}

void sessionFailure() {
  testWidgets('资料编辑中会话失效，旧资料和输入均销毁', (tester) async {
    final fixture = OnlineFixture()..seed();
    await openDetail(tester, fixture);
    await online.tap(tester, '编辑其他案件信息');
    await fill(tester, '备注', '虚构尚未提交');
    fixture.expire = true;
    await online.tap(tester, '保存案件资料');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(CaseSupplementEditor), findsNothing);
    expect(find.textContaining('虚构尚未提交'), findsNothing);
  });
}

void pendingSave() {
  testWidgets('保存期间禁用输入、状态、按钮及系统返回，只提交一次', (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => CaseSupplementEditor(
                    initial: const CaseSupplement(),
                    save: (_) {
                      calls++;
                      return gate.future;
                    },
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await online.tap(tester, '打开');
    await tester.tap(find.text('保存案件资料'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('审判员'))).enabled,
      false,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CaseSupplementEditor), findsOneWidget);
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CaseSupplementEditor), findsNothing);
  });
}

void offlineExperience() {
  testWidgets('320 窄屏深色离线六项资料可编辑，返回重进保留，清空可恢复', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await demo.enter(tester);
    await demo.createCase(tester);
    await online.tap(tester, '案件详情与当事人');
    await online.tap(tester, '编辑其他案件信息');
    await fill(tester, '审判员', '虚构审判员');
    await fill(tester, '书记员', '虚构书记员');
    await fill(tester, '书记员电话', '虚构电话');
    await fill(tester, '费用金额（元）', '123.4');
    await status(tester, '已付');
    await fill(tester, '备注', '虚构体验备注');
    await online.tap(tester, '保存体验资料');
    expect(find.text('费用（元）：123.40 · 已付'), findsOneWidget);
    await captureOnline(
      tester,
      fileName: 'client-case-supplement-demo.png',
      key: demo.captureKey,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await online.tap(tester, '案件详情与当事人');
    expect(find.text('备注：虚构体验备注'), findsOneWidget);
    await online.tap(tester, '编辑其他案件信息');
    await fill(tester, '备注', '');
    await online.tap(tester, '保存体验资料');
    expect(find.text('备注：未填写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
