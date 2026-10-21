import 'dart:async';
import 'package:dio/dio.dart';
import 'api_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'online_widget_test.dart' as online;
import 'party_widget_test.dart' as party;
import 'experience_widget_test.dart' as demo;
import 'online_fixture.dart';
import 'online_evidence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  onlineCreation();
  cancelCreation();
  offlineCreation();
  pendingCreate();
  expiredCreate();
}

Future<void> fillCase(WidgetTester tester) async {
  const values = ['(2026)虚构民初2号', '虚构案由', '虚构法院', '虚构原告'];
  for (var i = 0; i < values.length; i++) {
    await tester.enterText(find.byType(TextFormField).at(i), values[i]);
  }
}

Future<void> addDefendant(WidgetTester tester) async {
  await online.tap(tester, '编辑新建名单（1 人）');
  await online.tap(tester, '添加当事人（1/100）');
  await party.fillName(tester, 2, '虚构被告');
  await online.tap(tester, '完成名单');
}

void onlineCreation() {
  testWidgets('新建多人失败保留整份草稿，重试一次创建完整名单并可读取详情', (tester) async {
    final fixture = OnlineFixture();
    await online.start(tester, fixture);
    await online.login(tester);
    await online.tap(tester, '新建测试案件');
    await fillCase(tester);
    await addDefendant(tester);
    expect(fixture.records, isEmpty);
    fixture.failWrite = true;
    await online.tap(tester, '保存到测试服务');
    expect(find.textContaining('记录重复'), findsOneWidget);
    expect(find.text('被告 · 虚构被告'), findsOneWidget);
    expect(fixture.records, isEmpty);
    fixture.failWrite = false;
    await online.tap(tester, '保存到测试服务');
    final parties = fixture.records.single['parties'] as List;
    expect(parties.map((p) => p['name']), ['虚构原告', '虚构被告']);
    expect(parties.last['role'], 'DEFENDANT');
    expect(fixture.requests.where((r) => r == 'POST /cases').length, 2);
    expect(fixture.requests.where((r) => r.startsWith('PATCH')), isEmpty);
    await online.tap(tester, '(2026)虚构民初2号');
    await online.tap(tester, '案件详情与当事人');
    expect(find.text('原告 · 虚构原告'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('被告 · 虚构被告'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('被告 · 虚构被告'), findsOneWidget);
  });
}

void cancelCreation() {
  testWidgets('取消名单恢复原草稿，取消整个新建不请求服务端', (tester) async {
    final fixture = OnlineFixture();
    await online.start(tester, fixture);
    await online.login(tester);
    await online.tap(tester, '新建测试案件');
    await fillCase(tester);
    await addDefendant(tester);
    await online.tap(tester, '编辑新建名单（2 人）');
    await party.fillName(tester, 1, '虚构丢弃修改');
    await online.tap(tester, '取消编辑');
    expect(find.text('原告 · 虚构原告'), findsOneWidget);
    expect(find.textContaining('虚构丢弃修改'), findsNothing);
    await online.tap(tester, '取消');
    expect(fixture.records, isEmpty);
    expect(fixture.requests.where((r) => r == 'POST /cases'), isEmpty);
  });
}

void offlineCreation() {
  testWidgets('窄屏离线新建多人，保存后能看到完整名单且明确不进行历史匹配', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await demo.enter(tester);
    await online.tap(tester, '新建案件');
    await addDefendant(tester);
    await captureOnline(
      tester,
      fileName: 'client-create-parties.png',
      key: demo.captureKey,
    );
    await online.tap(tester, '创建体验案件');
    await online.tap(tester, '案件详情与当事人');
    expect(find.text('当事人（2）'), findsOneWidget);
    await tester.ensureVisible(find.text('被告 · 虚构被告'));
    expect(find.text('被告 · 虚构被告'), findsOneWidget);
    expect(find.textContaining('离线体验不执行历史姓名匹配'), findsOneWidget);
    expect(find.text('检查利益冲突'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class PendingCreateFixture extends OnlineFixture {
  final gate = Completer<void>();
  int creates = 0;
  @override
  Dio dio() => Dio()
    ..httpClientAdapter = TestAdapter((request) async {
      if (request.method == 'POST' && request.path == '/cases') {
        creates++;
        await gate.future;
      }
      return handle(request);
    });
}

void pendingCreate() {
  testWidgets('创建未返回时防连点与返回，名单不能改动且只发送一次', (tester) async {
    final fixture = PendingCreateFixture();
    await online.start(tester, fixture);
    await online.login(tester);
    await online.tap(tester, '新建测试案件');
    await fillCase(tester);
    await addDefendant(tester);
    await tester.tap(find.text('保存到测试服务'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存中…'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '编辑新建名单（2 人）'),
          )
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fixture.creates, 1);
    fixture.gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect((fixture.records.single['parties'] as List).length, 2);
  });
}

void expiredCreate() {
  testWidgets('多人新建会话失效销毁表单和草稿，不保留到下次登录', (tester) async {
    final fixture = OnlineFixture();
    await online.start(tester, fixture);
    await online.login(tester);
    await online.tap(tester, '新建测试案件');
    await fillCase(tester);
    await addDefendant(tester);
    fixture.expire = true;
    await online.tap(tester, '保存到测试服务');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.text('被告 · 虚构被告'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.records, isEmpty);
  });
}
