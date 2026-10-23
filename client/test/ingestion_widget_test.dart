import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/presentation/ingestion_editor.dart';
import 'package:ruler_client/presentation/ingestion_page.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'ingestion_fixture.dart';
import 'online_evidence.dart';
import 'online_widget_test.dart' as online;

Future<void> open(WidgetTester tester, IngestionFixture fixture) async {
  await online.start(tester, fixture);
  await online.login(tester);
  await tester.tap(find.byTooltip('材料待定区'));
  await tester.pumpAndSettle();
}

Future<void> input(WidgetTester tester, String text) async {
  await online.tap(tester, '粘贴转发文字');
  await tester.enterText(find.byType(TextField), text);
  await online.tap(tester, '保存到待定区');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  lifecycle();
  recovery();
  pagination();
  pending();
  expiry();
  offline();
  validation();
}

void lifecycle() {
  testWidgets('接收文字、完整原文、重复提示与忽略确认历史闭环', (tester) async {
    final fixture = IngestionFixture();
    await open(tester, fixture);
    expect(find.text('暂无待定材料'), findsOneWidget);
    final text = '虚构微信转发：收到材料，请核对归属。\n${'虚构正文' * 60}';
    await input(tester, text);
    expect(find.text('已保存到待定区。'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-ingestion.png');
    await online.tap(tester, '查看原文');
    expect(find.text(text), findsOneWidget);
    await online.tap(tester, '关闭');
    await input(tester, text);
    expect(find.textContaining('未重复创建'), findsOneWidget);
    expect(fixture.entries.length, 1);
    await online.tap(tester, '忽略材料');
    await online.tap(tester, '取消');
    expect(fixture.entries.single['status'], 'PENDING_MATCH');
    await online.tap(tester, '忽略材料');
    await online.tap(tester, '确认忽略');
    expect(find.text('暂无待定材料'), findsOneWidget);
    await online.tap(tester, '归集历史');
    expect(find.text('微信转发 · 已忽略'), findsOneWidget);
    expect(find.text('忽略材料'), findsNothing);
    await input(tester, text);
    expect(find.textContaining('当前已忽略'), findsOneWidget);
    expect(fixture.entries.length, 1);
  });
}

void recovery() {
  testWidgets('接收响应丢失保留输入且重试不重复；忽略后读失败只重读', (tester) async {
    final fixture = IngestionFixture()..loseReceiveReply = true;
    await open(tester, fixture);
    await input(tester, '虚构网络重试');
    expect(find.byType(IngestionEditor), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '虚构网络重试',
    );
    expect(find.textContaining('unsafe'), findsNothing);
    await online.tap(tester, '保存到待定区');
    expect(fixture.entries.length, 1);
    fixture.failWrite = true;
    await online.tap(tester, '忽略材料');
    await online.tap(tester, '确认忽略');
    expect(fixture.entries.single['status'], 'PENDING_MATCH');
    fixture.failWrite = false;
    fixture.failAfterWrite = true;
    await online.tap(tester, '忽略材料');
    await online.tap(tester, '确认忽略');
    expect(find.text('虚构网络重试'), findsNothing);
    fixture.failRead = false;
    await online.tap(tester, '重新加载');
    expect(find.text('暂无待定材料'), findsOneWidget);
    expect(fixture.requests.where((r) => r.endsWith('/ignore')).length, 2);
  });
}

void pagination() {
  testWidgets('跨页忽略回第一页；详情失败独立重读，刷新不显示旧列表', (tester) async {
    final fixture = IngestionFixture()
      ..entries.addAll(List.generate(21, ingestionRow));
    await open(tester, fixture);
    await online.tap(tester, '下一页');
    expect(find.text('第 2 页 · 共 21 条'), findsOneWidget);
    fixture.failRead = true;
    await online.tap(tester, '查看原文');
    expect(find.byType(SelectableText), findsNothing);
    fixture.failRead = false;
    await online.tap(tester, '重新加载');
    expect(find.byType(SelectableText), findsOneWidget);
    await online.tap(tester, '关闭');
    await online.tap(tester, '忽略材料');
    await online.tap(tester, '确认忽略');
    expect(find.text('第 1 页 · 共 20 条'), findsOneWidget);
    fixture.failRead = true;
    await tester.tap(find.byTooltip('刷新材料'));
    await tester.pumpAndSettle();
    expect(find.text('虚构转发文字0'), findsNothing);
    fixture.failRead = false;
    await online.tap(tester, '重新加载');
    expect(find.text('虚构转发文字0'), findsOneWidget);
  });
}

void pending() {
  testWidgets('接收与忽略等待期间禁止返回和连点', (tester) async {
    final fixture = IngestionFixture()..writeGate = Completer<void>();
    await open(tester, fixture);
    await online.tap(tester, '粘贴转发文字');
    await tester.enterText(find.byType(TextField), '虚构等待');
    await tester.tap(find.text('保存到待定区'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(IngestionEditor), findsOneWidget);
    await tester.tap(find.text('保存中…'), warnIfMissed: false);
    fixture.writeGate!.complete();
    await tester.pumpAndSettle();
    fixture.writeGate = Completer<void>();
    await online.tap(tester, '忽略材料');
    await tester.tap(find.text('确认忽略'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(IngestionPage), findsOneWidget);
    fixture.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(
      fixture.requests.where((r) => r == 'POST /ingestion/wechat').length,
      1,
    );
    expect(fixture.requests.where((r) => r.endsWith('/ignore')).length, 1);
  });
}

void expiry() {
  testWidgets('会话失效销毁待定区和原文对话框，不能返回旧账号数据', (tester) async {
    final fixture = IngestionFixture()..entries.add(ingestionRow());
    await open(tester, fixture);
    fixture.expire = true;
    await online.tap(tester, '查看原文');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(IngestionPage), findsNothing);
    expect(find.text('材料原文'), findsNothing);
    expect(find.text('虚构转发文字0'), findsNothing);
  });
}

void offline() {
  testWidgets('窄屏深色虚构文字可接收查看忽略，返回案件再进保留本次内存', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      const ProviderScope(
        child: RepaintBoundary(key: onlineCaptureKey, child: RulerApp()),
      ),
    );
    await tester.pumpAndSettle();
    await online.tap(tester, '开始虚构体验');
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await input(tester, '虚构转发：请核对起诉材料、法院文件与服务合同的归属。');
    await captureOnline(tester, fileName: 'client-ingestion-demo.png');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 页 · 共 1 条'), findsOneWidget);
    await online.tap(tester, '忽略材料');
    await online.tap(tester, '确认忽略');
    await online.tap(tester, '归集历史');
    expect(find.text('微信转发 · 已忽略'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void validation() {
  testWidgets('空文字不发请求，取消草稿不入库', (tester) async {
    final fixture = IngestionFixture();
    await open(tester, fixture);
    await input(tester, ' ');
    expect(find.text('请填写虚构转发文字。'), findsOneWidget);
    expect(
      fixture.requests.where((r) => r == 'POST /ingestion/wechat'),
      isEmpty,
    );
    await online.tap(tester, '取消');
    expect(fixture.entries, isEmpty);
  });
}
