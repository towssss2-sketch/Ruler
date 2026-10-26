import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/experience_provider.dart';
import 'package:ruler_client/application/ingestion_provider.dart';
import 'package:ruler_client/application/online_provider.dart';
import 'package:ruler_client/domain/ingestion_preview.dart';
import 'package:ruler_client/presentation/ingestion_page.dart';
import 'package:ruler_client/presentation/ingestion_preview_dialog.dart';
import 'package:ruler_client/presentation/ingestion_assign_dialog.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'ingestion_preview_fixture.dart';
import 'ingestion_fixture.dart';
import 'ingestion_file_api_fixture.dart' show attachment;
import 'ingestion_assign_widget_test.dart' show choose;
import 'online_widget_test.dart' as online;
import 'online_widget_test.dart' show tap;
import 'online_evidence.dart';

Future<void> open(WidgetTester tester, PreviewFixture f) async {
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
  await tap(tester, '提取正文');
}

void main() {
  setUpAll(prepareOnlineFont);
  success();
  recovery();
  lifecycle();
  offline();
  expiry();
}

void success() {
  testWidgets('显示正文与待确认案号；建议只预选类别，取消无写入，仍可改选全部分类', (tester) async {
    final f = PreviewFixture();
    await open(tester, f);
    expect(find.text('建议分类：服务合同'), findsOneWidget);
    expect(find.text('候选案号（尚未匹配案件）'), findsOneWidget);
    expect(find.text('法律服务合同\n仅为虚构联调正文。'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-ingestion-preview.png');
    await tap(tester, '按建议选择分类');
    expect(find.byType(IngestionPreviewDialog), findsNothing);
    expect(find.byType(IngestionAssignDialog), findsOneWidget);
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(field.initialValue, 'SERVICE_CONTRACT');
    expect(f.assigned.attempts, 0);
    await tap(tester, '取消');
    expect(f.assigned.attempts, 0);
    await tap(tester, '提取正文');
    await tap(tester, '按建议选择分类');
    await choose(tester, category: '法院文件');
    await tap(tester, '确认归档');
    expect(
      (await f.assigned.experience.load()).single.files.single.category,
      'COURT_DOCUMENT',
    );
  });
  testWidgets('冲突及未知标题不提供建议归档；案号截断提示明确，正文链接只按文字展示', (tester) async {
    final f = PreviewFixture()
      ..result = previewResult(
        category: null,
        reason: 'CONFLICTING_TITLES',
        truncated: true,
        text: '虚构引用 <script>不执行</script> https://example.invalid/不访问',
      );
    await open(tester, f);
    expect(find.text('标题存在冲突，请手动选择分类。'), findsOneWidget);
    expect(find.text('按建议选择分类'), findsNothing);
    expect(find.textContaining('仅显示前 10 个'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(f.calls, 1);
    f.result = previewResult(category: null, reason: 'NO_TITLE');
    await tap(tester, '重新提取');
    expect(find.text('没有明确的分类建议，请手动选择。'), findsOneWidget);
  });
}

void recovery() {
  testWidgets('失败显式重试；重试前清除旧正文，成功不会自动保存或归档', (tester) async {
    final f = PreviewFixture()..fail = true;
    await open(tester, f);
    expect(find.text('正文提取暂不可用，请稍后重试。'), findsOneWidget);
    expect(f.calls, 1);
    f.fail = false;
    await tap(tester, '重试提取');
    expect(f.calls, 2);
    f.gate = Completer<void>();
    await tester.tap(find.text('重新提取'));
    await tester.pump();
    expect(find.byType(SelectableText), findsNothing);
    expect(f.calls, 3);
    expect(find.text('按建议选择分类'), findsNothing);
    f.fail = true;
    f.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
    expect(f.assigned.attempts, 0);
  });
  testWidgets('所有人工处理原因有中文说明，仅暂时故障可重试，原件仍可手工处理', (tester) async {
    final f = PreviewFixture();
    await open(tester, f);
    for (final reason in previewReasons.keys) {
      await tap(tester, '关闭');
      f.result = IngestionPreviewResult(
        attemptId: 'fixture',
        reason: reason,
        retryable: ['TIMEOUT', 'UNAVAILABLE'].contains(reason),
      );
      await tap(tester, '提取正文');
      expect(find.text(previewReasons[reason]!), findsOneWidget);
      expect(find.text('按建议选择分类'), findsNothing);
      expect(
        find.text('重试提取'),
        f.result.retryable ? findsOneWidget : findsNothing,
      );
      if (reason == 'NO_TEXT') {
        await captureOnline(
          tester,
          fileName: 'client-ingestion-preview-manual.png',
        );
      }
    }
    expect(f.assigned.attempts, 0);
  });
  testWidgets('使用建议前独立重读：核对失败或已忽略不归档，旧页面不覆盖新状态', (tester) async {
    final f = PreviewFixture();
    await open(tester, f);
    f.inbox.failDetail = true;
    await tap(tester, '按建议选择分类');
    expect(find.text('材料状态核对失败，请重试。'), findsOneWidget);
    expect(find.byType(IngestionAssignDialog), findsNothing);
    expect(f.assigned.attempts, 0);
    f.inbox.failDetail = false;
    await tap(tester, '提取正文');
    final id = (await f.inbox.list()).items.single.id;
    await f.inbox.ignore(id);
    await tap(tester, '按建议选择分类');
    expect(find.text('材料状态已改变，请刷新核对后再归档。'), findsOneWidget);
    expect(find.byType(IngestionAssignDialog), findsNothing);
    expect(f.assigned.attempts, 0);
  });
}

void lifecycle() {
  testWidgets('窄屏大字长正文可以滚动到末尾，不截断正文或造成布局溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = PreviewFixture()
      ..result = previewResult(text: '虚构正文\n' * 12000 + '虚构正文结束');
    await f.assigned.prepare();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: IngestionPage(
          repository: f.inbox,
          preview: f,
          assignment: f.assigned,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, '提取正文');
    expect(
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!
          .endsWith('虚构正文结束'),
      true,
    );
    final scrolling = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(IngestionPreviewDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrolling.position.jumpTo(scrolling.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(scrolling.position.pixels, scrolling.position.maxScrollExtent);
    expect(tester.takeException(), isNull);
    await tap(tester, '关闭');
  });
  testWidgets('等待中不重复提交，关闭后迟到正文不再显示，重新打开才发新请求', (tester) async {
    final f = PreviewFixture();
    await open(tester, f);
    await tap(tester, '关闭');
    f.gate = Completer<void>();
    await tester.tap(find.text('提取正文'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(f.calls, 2);
    expect(find.text('重新提取'), findsNothing);
    await tap(tester, '关闭');
    f.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(IngestionPreviewDialog), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    f.gate = null;
    await tap(tester, '提取正文');
    expect(f.calls, 3);
  });
  testWidgets('已归档/忽略历史仍可预览，不能从建议绕过现有状态；文字没有文件提取入口', (tester) async {
    final f = PreviewFixture();
    await open(tester, f);
    await tap(tester, '关闭');
    final id = (await f.inbox.list()).items.single.id;
    await f.assigned.repository.assign(
      id,
      f.assigned.caseId,
      'SERVICE_CONTRACT',
    );
    await f.inbox.receive('虚构纯文字');
    await tap(tester, '归集历史');
    expect(find.text('提取正文'), findsOneWidget);
    await tap(tester, '提取正文');
    expect(find.text('建议分类：服务合同'), findsOneWidget);
    expect(find.text('按建议选择分类'), findsNothing);
  });
}

void offline() {
  testWidgets('320宽深色真实离线流程：虚构正文→建议分类→选案确认→服务合同归档', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final f = PreviewFixture();
    await f.assigned.prepare();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          experienceRepositoryProvider.overrideWithValue(f.assigned.experience),
          experienceIngestionProvider.overrideWithValue(f.assigned.inbox),
        ],
        child: const RepaintBoundary(key: onlineCaptureKey, child: RulerApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, '开始虚构体验');
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tap(tester, '查看正文示例');
    expect(find.text('预置示例，不读取设备或解析真实文件。'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-ingestion-preview-demo.png');
    await tap(tester, '按建议选择分类');
    await choose(tester, category: '服务合同');
    await tap(tester, '确认归档');
    expect(
      (await f.assigned.experience.load()).single.files.single.category,
      'SERVICE_CONTRACT',
    );
    expect(tester.takeException(), isNull);
  });
}

void expiry() {
  testWidgets('真实会话在重新提取时失效，移除已显示的正文和材料页面', (tester) async {
    final f = PreviewSessionFixture()
      ..entries.add({...ingestionRow(), 'file': attachment()});
    await online.start(tester, f);
    await online.login(tester);
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tap(tester, '提取正文');
    expect(find.text('建议分类：服务合同'), findsOneWidget);
    f.expire = true;
    await tap(tester, '重新提取');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(IngestionPreviewDialog), findsNothing);
    expect(find.byType(IngestionPage), findsNothing);
    expect(find.text('法律服务合同\n仅为虚构联调正文。'), findsNothing);
  });
  testWidgets('会话退出时销毁等待中的弹窗，晚到响应不能恢复旧账号正文', (tester) async {
    final f = PreviewSessionFixture()
      ..entries.add({...ingestionRow(), 'file': attachment()});
    await online.start(tester, f);
    await online.login(tester);
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IngestionPage)),
    );
    f.writeGate = Completer<void>();
    await tester.tap(find.text('提取正文'));
    await tester.pump();
    final logout = container.read(onlineProvider.notifier).logout();
    await tester.pumpAndSettle();
    await logout;
    expect(find.text('测试账号登录'), findsOneWidget);
    f.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(IngestionPreviewDialog), findsNothing);
  });
}
