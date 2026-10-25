import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/experience_provider.dart';
import 'package:ruler_client/application/ingestion_provider.dart';
import 'package:ruler_client/presentation/ingestion_page.dart';
import 'package:ruler_client/presentation/ingestion_archive_dialog.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'ingestion_archive_fixture.dart';
import 'ingestion_assign_widget_test.dart' show choose;
import 'online_widget_test.dart' show tap;
import 'online_evidence.dart';
import 'ingestion_fixture.dart';
import 'ingestion_file_api_fixture.dart' show attachment;
import 'online_widget_test.dart' as online;

Future<void> open(
  WidgetTester tester,
  ArchiveFixture f, {
  void Function(String)? opened,
}) async {
  await f.prepare();
  await tester.pumpWidget(
    RepaintBoundary(
      key: onlineCaptureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: IngestionPage(
          repository: f.assigned.inbox,
          assignment: f.assigned.repository,
          archive: f,
          openCase: (item) async {
            opened?.call(item.id);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tap(tester, '归集历史');
  await tap(tester, '归档去向');
}

void main() {
  setUpAll(prepareOnlineFont);
  location();
  recovery();
  busy();
  offline();
  expiry();
}

void location() {
  testWidgets('显示案号法院分类，打开所属案件后仍可回到材料列表', (tester) async {
    final f = ArchiveFixture();
    String? selected;
    await open(tester, f, opened: (id) => selected = id);
    expect(find.text('文件分类：服务合同'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-ingestion-location.png');
    await tap(tester, '打开所属案件');
    expect(selected, f.assigned.caseId);
    expect(find.byType(IngestionArchiveDialog), findsNothing);
    expect(find.text('微信转发 · 已指派'), findsOneWidget);
  });
  testWidgets('去向失败重试、不可用和版本阻塞提示，取消撤回没有写入', (tester) async {
    final f = ArchiveFixture()..failRead = true;
    await open(tester, f);
    expect(find.text('去向暂不可用。'), findsOneWidget);
    f.failRead = false;
    await tap(tester, '重新加载');
    await tap(tester, '撤回待定区');
    await tap(tester, '取消');
    expect(f.writes, 0);
    f.blocked = true;
    await tap(tester, '刷新去向');
    expect(find.text('撤回待定区'), findsNothing);
    expect(find.textContaining('其他保留版本'), findsOneWidget);
    f.unavailable = true;
    await tap(tester, '刷新去向');
    expect(find.textContaining('已不可用'), findsOneWidget);
    expect(find.text('打开所属案件'), findsNothing);
  });
}

void recovery() {
  testWidgets('撤回失败保留本次身份，响应丢失重复确认幂等，列表读失败仅重读', (tester) async {
    final f = ArchiveFixture()..failWrite = true;
    await open(tester, f);
    await tap(tester, '撤回待定区');
    await tap(tester, '确认撤回');
    expect(find.text('撤回未完成，请重试。'), findsOneWidget);
    f.failWrite = false;
    f.loseReply = true;
    await tap(tester, '撤回待定区');
    await tap(tester, '确认撤回');
    expect(find.text('撤回结果未确认，请重试。'), findsOneWidget);
    f.failList = true;
    await tap(tester, '撤回待定区');
    await tap(tester, '确认撤回');
    expect(find.text('列表暂不可用。'), findsOneWidget);
    expect(f.writes, 3);
    f.assigned.inbox.failRead = false;
    await tap(tester, '重新加载');
    expect(find.text('微信转发 · 待定'), findsOneWidget);
    expect(f.writes, 3);
    expect((await f.assigned.inbox.detail(f.id)).assignmentRevision, 1);
  });
}

void busy() {
  testWidgets('撤回等待禁用重复点击和返回，完成后返回待定可重新归档', (tester) async {
    final f = ArchiveFixture()..gate = Completer<void>();
    await open(tester, f);
    await tap(tester, '撤回待定区');
    await tester.tap(find.text('确认撤回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(IngestionArchiveDialog), findsOneWidget);
    expect(f.writes, 1);
    f.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('分类归档'), findsOneWidget);
    await tap(tester, '分类归档');
    await choose(tester, category: '法院文件');
    await tap(tester, '确认归档');
    expect(
      (await f.assigned.experience.load()).single.files.single.category,
      'COURT_DOCUMENT',
    );
  });
}

void offline() {
  testWidgets('窄屏深色真实离线导航：看去向、进入案件、返回撤回、重新选择分类', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final f = ArchiveFixture();
    await f.prepare();
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
    await tap(tester, '归集历史');
    await tap(tester, '归档去向');
    await tap(tester, '打开所属案件');
    await tap(tester, '示例文件');
    expect(find.text('虚构服务合同示例.pdf'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tap(tester, '归档去向');
    await tap(tester, '撤回待定区');
    await captureOnline(tester, fileName: 'client-ingestion-withdraw-demo.png');
    await tap(tester, '确认撤回');
    await tap(tester, '分类归档');
    await choose(tester, category: '法院文件');
    await tap(tester, '确认归档');
    await tap(tester, '归档去向');
    expect(find.text('文件分类：法院文件'), findsOneWidget);
    await captureOnline(
      tester,
      fileName: 'client-ingestion-reassigned-demo.png',
    );
    expect(tester.takeException(), isNull);
  });
}

void expiry() {
  testWidgets('撤回确认期间会话失效清除旧账号材料和去向，不保留弹窗', (tester) async {
    final f = ArchiveSessionFixture()
      ..entries.add({
        ...ingestionRow(),
        'status': 'ASSIGNED',
        'file': attachment(),
      });
    await online.start(tester, f);
    await online.login(tester);
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tap(tester, '归集历史');
    await tap(tester, '归档去向');
    await tap(tester, '撤回待定区');
    f.expire = true;
    await tap(tester, '确认撤回');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(IngestionArchiveDialog), findsNothing);
    expect(find.byType(IngestionPage), findsNothing);
    expect(find.text('虚构案号'), findsNothing);
  });
}
