import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/ingestion_provider.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/domain/preview_attempts.dart';
import 'package:ruler_client/presentation/ingestion_page.dart';
import 'package:ruler_client/presentation/ingestion_preview_dialog.dart';
import 'package:ruler_client/presentation/preview_attempts_dialog.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'preview_attempt_fixture.dart';
import 'ingestion_fixture.dart';
import 'ingestion_file_api_fixture.dart' show attachment;
import 'online_widget_test.dart' as online;
import 'online_widget_test.dart' show tap;
import 'online_evidence.dart';

Future<void> open(WidgetTester tester, AttemptFixture f) async {
  await f.assigned.prepare();
  await tester.pumpWidget(
    RepaintBoundary(
      key: onlineCaptureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: IngestionPage(
          repository: f.inbox,
          preview: f,
          assignment: f.assigned,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('提取记录'));
  await tester.pumpAndSettle();
  await tap(tester, '提取记录');
}

Future<void> historyTap(WidgetTester tester, String label) async {
  final finder = find.descendant(
    of: find.byType(PreviewAttemptsDialog),
    matching: find.text(label),
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(prepareOnlineFont);
  testWidgets('读取中断历史不发起提取，明确重试才调用原预览并仍需人工确认归档', (tester) async {
    final f = AttemptFixture();
    await open(tester, f);
    expect(find.text('处理已中断'), findsOneWidget);
    expect(f.calls, 0);
    expect(find.textContaining('08:00:00'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-preview-attempts.png');
    await tap(tester, '重新提取正文');
    expect(find.byType(PreviewAttemptsDialog), findsNothing);
    expect(find.byType(IngestionPreviewDialog), findsOneWidget);
    expect(f.calls, 1);
    expect(f.assigned.attempts, 0);
    await tap(tester, '关闭');
    expect(f.assigned.attempts, 0);
  });
  testWidgets('处理中/成功/不可重试失败/空记录不提供自动重试，暂时故障可主动重试', (tester) async {
    final f = AttemptFixture()..status = 'RUNNING';
    await open(tester, f);
    expect(find.text('处理中'), findsOneWidget);
    expect(find.text('重新提取正文'), findsNothing);
    f.status = 'SUCCEEDED';
    await tap(tester, '刷新记录');
    expect(find.textContaining('不代表已归档'), findsOneWidget);
    f.status = 'MANUAL_REQUIRED';
    f.reason = 'NO_TEXT';
    await tap(tester, '刷新记录');
    expect(find.textContaining('扫描件或图片'), findsOneWidget);
    expect(find.text('重新提取正文'), findsNothing);
    f.reason = 'TIMEOUT';
    await tap(tester, '刷新记录');
    expect(find.text('重新提取正文'), findsOneWidget);
    f.total = 0;
    await tap(tester, '刷新记录');
    expect(find.text('尚无提取记录'), findsOneWidget);
    expect(f.calls, 0);
    expect(find.text('重新提取正文'), findsNothing);
  });
  testWidgets('分页滚动可达，失败重读保持页码；刷新回首页且不自动触发提取', (tester) async {
    final f = AttemptFixture()..total = 21;
    await open(tester, f);
    await historyTap(tester, '下一页');
    expect(f.pages.last, 2);
    expect(find.text('重新提取正文'), findsNothing);
    f.failRead = true;
    await historyTap(tester, '上一页');
    expect(find.text('记录暂不可用，请重试。'), findsOneWidget);
    expect(find.text('尚无提取记录'), findsNothing);
    f.failRead = false;
    await tap(tester, '重新加载');
    expect(f.pages.last, 1);
    await historyTap(tester, '下一页');
    await tap(tester, '刷新记录');
    expect(f.pages.last, 1);
    expect(f.calls, 0);
  });
  testWidgets('关闭和刷新后迟到记录不能恢复旧内容或窗口', (tester) async {
    final f = AttemptFixture();
    await open(tester, f);
    final gate = Completer<OnlinePage<PreviewAttempt>>();
    f.pending = gate;
    await tester.tap(find.text('刷新记录'));
    await tester.pump();
    expect(find.text('重新提取正文'), findsNothing);
    f.pending = null;
    f.status = 'SUCCEEDED';
    await tap(tester, '刷新记录');
    gate.complete(OnlinePage([], 0, 1));
    await tester.pumpAndSettle();
    expect(find.text('提取成功'), findsOneWidget);
    final closing = Completer<OnlinePage<PreviewAttempt>>();
    f.pending = closing;
    await tester.tap(find.text('刷新记录'));
    await tester.pump();
    await tap(tester, '关闭');
    closing.complete(OnlinePage([], 0, 1));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewAttemptsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('记录401会话失效销毁页面，不继续显示历史或重试按钮', (tester) async {
    final f = IngestionFixture()
      ..entries.add({...ingestionRow(), 'file': attachment()});
    await online.start(tester, f);
    await online.login(tester);
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    f.expire = true;
    await tester.ensureVisible(find.text('提取记录'));
    await tester.pumpAndSettle();
    await tap(tester, '提取记录');
    expect(find.byType(PreviewAttemptsDialog), findsNothing);
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.text('重新提取正文'), findsNothing);
  });
  testWidgets('真实离线320宽深色大字：空记录→查看示例→成功记录，返回再进仍保留', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(experienceIngestionProvider).addFileExample();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RepaintBoundary(key: onlineCaptureKey, child: RulerApp()),
      ),
    );
    await tap(tester, '开始虚构体验');
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('提取记录'));
    await tester.pumpAndSettle();
    await tap(tester, '提取记录');
    expect(find.text('尚无提取记录'), findsOneWidget);
    await tap(tester, '关闭');
    await tester.ensureVisible(find.text('查看正文示例'));
    await tester.pumpAndSettle();
    await tap(tester, '查看正文示例');
    await tap(tester, '关闭');
    await tester.ensureVisible(find.text('提取记录'));
    await tester.pumpAndSettle();
    await tap(tester, '提取记录');
    expect(find.text('提取成功'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-preview-attempts-demo.png');
    await tap(tester, '关闭');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('提取记录'));
    await tester.pumpAndSettle();
    await tap(tester, '提取记录');
    expect(
      find.descendant(
        of: find.byType(PreviewAttemptsDialog),
        matching: find.text('第 1 页 · 共 1 条'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
