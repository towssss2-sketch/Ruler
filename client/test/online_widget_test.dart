import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/online_provider.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'online_fixture.dart';
import 'online_evidence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  testWidgets('未提供服务地址时明确提示，登录按钮不可点击', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RulerApp()));
    await tester.tap(find.text('测试服务登录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('测试服务尚未开放'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '登录测试服务'))
          .onPressed,
      isNull,
    );
  });
  registerScenario2();
  registerScenario3();
  registerScenario4();
  registerScenario5();
  registerScenario6();
}

void registerScenario2() {
  testWidgets('错误密码不回显原文，重试登录后能退出', (tester) async {
    final server = OnlineFixture()..denyLogin = true;
    await start(tester, server);
    await login(tester);
    expect(find.text('邮箱或密码不正确。'), findsOneWidget);
    expect(find.text('unsafe-server-payload'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      isEmpty,
    );
    server.denyLogin = false;
    await login(tester);
    expect(find.text('我的测试案件'), findsOneWidget);
    await tap(tester, '退出登录');
    expect(find.text('测试账号登录'), findsOneWidget);
  });
}

void registerScenario3() {
  testWidgets('登录、新建案件、新增任务、完成、恢复与删除确认', (tester) async {
    final server = OnlineFixture();
    await start(tester, server);
    await login(tester);
    await tap(tester, '新建测试案件');
    final values = ['(2026)虚构民初2号', '虚构合同纠纷', '虚构测试法院', '虚构甲'];
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), values[i]);
    }
    await tap(tester, '保存到测试服务');
    await tap(tester, values[0]);
    await tap(tester, '新增工作任务');
    await tester.enterText(find.byType(TextFormField).first, '虚构材料核对');
    await tester.enterText(find.byType(TextFormField).last, '2026-02-30');
    await tap(tester, '保存到测试服务');
    expect(find.text('请输入有效工作日期'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '2026-10-20');
    await tap(tester, '保存到测试服务');
    await tap(tester, '标记完成');
    expect(find.text('已完成 · 2026-10-20'), findsOneWidget);
    await captureOnline(tester);
    await tap(tester, '恢复待办');
    await tap(tester, '删除任务');
    await tap(tester, '取消');
    expect(find.text('虚构材料核对'), findsOneWidget);
    await tap(tester, '删除任务');
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await tester.pumpAndSettle();
    expect(find.text('暂无常规工作任务'), findsOneWidget);
    expect(server.work, isEmpty);
  });
}

void registerScenario4() {
  testWidgets('读取失败可重试，写入冲突保留表单', (tester) async {
    final server = OnlineFixture()..failRead = true;
    await start(tester, server);
    await login(tester);
    expect(find.text('重新加载'), findsOneWidget);
    server.failRead = false;
    await tap(tester, '重新加载');
    server.failWrite = true;
    await tap(tester, '新建测试案件');
    for (var i = 0; i < 4; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), '虚构输入');
    }
    await tap(tester, '保存到测试服务');
    expect(find.textContaining('记录重复'), findsOneWidget);
    expect(find.text('虚构输入'), findsNWidgets(4));
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}

void registerScenario5() {
  testWidgets('会话失效销毁旧案件详情和未关闭表单', (tester) async {
    final server = OnlineFixture()..seed();
    await start(tester, server);
    await login(tester);
    await tap(tester, '(2026)虚构民初1号');
    await tap(tester, '新增工作任务');
    await tester.enterText(find.byType(TextFormField).first, '虚构未保存任务');
    server.expire = true;
    await tap(tester, '保存到测试服务');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('(2026)虚构民初1号'), findsNothing);
    expect(server.work, isEmpty);
  });
}

void registerScenario6() {
  testWidgets('窄屏深色布局和系统返回保留正确导航层级', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final server = OnlineFixture()..seed();
    await start(tester, server);
    await login(tester);
    await tap(tester, '(2026)虚构民初1号');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('我的测试案件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> start(WidgetTester tester, OnlineFixture server) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiOriginProvider.overrideWithValue('https://example.invalid'),
        apiFactoryProvider.overrideWithValue(
          (origin, expired) =>
              ApiSession(origin, dio: server.dio(), onExpired: expired),
        ),
      ],
      child: const RepaintBoundary(key: onlineCaptureKey, child: RulerApp()),
    ),
  );
  await tap(tester, '测试服务登录');
}

Future<void> login(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextFormField).first,
    'fictional@example.invalid',
  );
  await tester.enterText(find.byType(TextFormField).last, 'fictional-password');
  await tap(tester, '登录测试服务');
}

Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
