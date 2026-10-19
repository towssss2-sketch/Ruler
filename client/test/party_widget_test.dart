import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/case_detail.dart';
import 'package:ruler_client/presentation/party_editor.dart';
import 'package:ruler_client/presentation/party_fields.dart';
import 'api_fixture.dart';
import 'online_evidence.dart';
import 'online_fixture.dart';
import 'online_widget_test.dart' as online;
import 'experience_widget_test.dart' as demo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  addAndRemove();
  writeFailure();
  readAfterWriteFailure();
  expiredSession();
  offlineExperience();
  pendingSave();
  fullListValidation();
}

Future<void> openDetail(WidgetTester tester, OnlineFixture fixture) async {
  await online.start(tester, fixture);
  await online.login(tester);
  await online.tap(tester, '(2026)虚构民初1号');
  await online.tap(tester, '案件详情与当事人');
}

Finder row(int index) => find.ancestor(
  of: find.text('当事人 $index'),
  matching: find.byType(PartyFieldsCard),
);
Future<void> showRow(WidgetTester tester, int index) async {
  await tester.scrollUntilVisible(
    find.text('当事人 $index'),
    300,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> fillName(WidgetTester tester, int index, String name) async {
  await showRow(tester, index);
  await tester.enterText(
    find.descendant(of: row(index), matching: find.byType(TextField)).first,
    name,
  );
}

void addAndRemove() {
  testWidgets('在线当事人新增、角色修改、清空电话及移除，不串行且刷新详情', (tester) async {
    final fixture = OnlineFixture()..seed();
    await openDetail(tester, fixture);
    expect(find.text('原告 · 虚构甲'), findsOneWidget);
    await online.tap(tester, '编辑当事人');
    await fillName(tester, 1, '虚构甲修改');
    await tester.enterText(
      find.descendant(of: row(1), matching: find.byType(TextField)).at(1),
      '',
    );
    await online.tap(tester, '添加当事人（1/100）');
    await fillName(tester, 2, '虚构乙');
    await tester.tap(
      find.descendant(
        of: row(2),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('第三人').last);
    await tester.pumpAndSettle();
    await captureOnline(tester, fileName: 'client-parties-editor.png');
    await online.tap(tester, '保存当事人');
    final parties = fixture.records.single['parties'] as List;
    expect(parties.first['id'], 'party-1');
    expect(parties.first['phone'], isNull);
    expect(parties.last['role'], 'THIRD_PARTY');
    await online.tap(tester, '编辑当事人');
    await tester.tap(find.descendant(of: row(1), matching: find.text('移除此人')));
    await tester.pumpAndSettle();
    await online.tap(tester, '确认移除');
    expect(find.widgetWithText(TextField, '虚构乙'), findsOneWidget);
    await online.tap(tester, '保存当事人');
    expect(find.text('第三人 · 虚构乙'), findsOneWidget);
    expect(find.text('原告 · 虚构甲修改'), findsNothing);
    await captureOnline(tester, fileName: 'client-parties-detail.png');
  });
}

void writeFailure() {
  testWidgets('写入失败保留输入和名单；取消不修改，重新加载后可重试保存', (tester) async {
    final fixture = OnlineFixture()..seed();
    await openDetail(tester, fixture);
    await online.tap(tester, '编辑当事人');
    await fillName(tester, 1, '虚构未保存');
    fixture.failWrite = true;
    await online.tap(tester, '保存当事人');
    expect(find.widgetWithText(TextField, '虚构未保存'), findsOneWidget);
    expect(find.textContaining('记录重复'), findsOneWidget);
    await online.tap(tester, '取消编辑');
    expect(find.text('原告 · 虚构甲'), findsOneWidget);
    fixture.failWrite = false;
    await online.tap(tester, '编辑当事人');
    await fillName(tester, 1, '虚构已保存');
    await online.tap(tester, '保存当事人');
    expect(find.text('原告 · 虚构已保存'), findsOneWidget);
  });
}

class ReadFailureFixture extends OnlineFixture {
  bool failNext = false;
  @override
  ResponseBody handle(RequestOptions request) {
    if (request.method == 'GET' &&
        request.path == '/cases/case-1' &&
        failNext) {
      failNext = false;
      return reply(null, 503);
    }
    final result = super.handle(request);
    if (request.method == 'PATCH') failNext = true;
    return result;
  }
}

void readAfterWriteFailure() {
  testWidgets('保存已成功但重读失败只重试读取，不重复 PATCH', (tester) async {
    final fixture = ReadFailureFixture()..seed();
    await openDetail(tester, fixture);
    await online.tap(tester, '编辑当事人');
    await fillName(tester, 1, '虚构已提交');
    await online.tap(tester, '保存当事人');
    expect(find.byType(PartyEditor), findsNothing);
    expect(find.text('重新加载'), findsOneWidget);
    await online.tap(tester, '重新加载');
    expect(find.text('原告 · 虚构已提交'), findsOneWidget);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')).length, 1);
  });
}

void expiredSession() {
  testWidgets('当事人编辑中会话失效销毁详情和输入', (tester) async {
    final fixture = OnlineFixture()..seed();
    await openDetail(tester, fixture);
    await online.tap(tester, '编辑当事人');
    await fillName(tester, 1, '虚构未提交姓名');
    fixture.expire = true;
    await online.tap(tester, '保存当事人');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(PartyEditor), findsNothing);
    expect(find.textContaining('虚构未提交姓名'), findsNothing);
  });
}

void offlineExperience() {
  testWidgets('窄屏深色离线可添加当事人，返回重进后仍保留本次名单', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await demo.enter(tester);
    await demo.createCase(tester);
    await online.tap(tester, '案件详情与当事人');
    expect(find.text('原告 · 虚构原告甲'), findsOneWidget);
    await online.tap(tester, '编辑当事人');
    await fillName(tester, 1, '虚构体验原告');
    await online.tap(tester, '保存体验当事人');
    expect(find.text('原告 · 虚构体验原告'), findsOneWidget);
    await captureOnline(
      tester,
      fileName: 'client-parties-demo.png',
      key: demo.captureKey,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await online.tap(tester, '案件详情与当事人');
    expect(find.text('原告 · 虚构体验原告'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void pendingSave() {
  testWidgets('保存期间按钮和系统返回禁用，成功后才退出', (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => PartyEditor(
                    parties: const [CaseParty(name: '虚构', role: 'PLAINTIFF')],
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
    await tester.tap(find.text('保存当事人'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PartyEditor), findsOneWidget);
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PartyEditor), findsNothing);
  });
}

void fullListValidation() {
  testWidgets('屏幕外空姓名仍阻止保存，单人不可移除，满百人不可新增', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PartyEditor(
          parties: [
            for (var i = 0; i < 99; i++)
              const CaseParty(name: '虚构', role: 'PLAINTIFF'),
            const CaseParty(name: '', role: 'DEFENDANT'),
          ],
          save: (_) async {
            calls++;
          },
        ),
      ),
    );
    await online.tap(tester, '保存当事人');
    expect(find.textContaining('第 100 位'), findsOneWidget);
    expect(calls, 0);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PartyEditor(
          key: const ValueKey('single'),
          parties: const [CaseParty(name: '虚构', role: 'PLAINTIFF')],
          save: (_) async {},
        ),
      ),
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '移除此人'))
          .onPressed,
      isNull,
    );
  });
}
