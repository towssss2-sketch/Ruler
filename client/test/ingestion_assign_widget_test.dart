import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/experience_provider.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/presentation/ingestion_page.dart';
import 'package:ruler_client/presentation/ingestion_assign_dialog.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'ingestion_assign_fixture.dart';
import 'ingestion_fixture.dart';
import 'ingestion_file_api_fixture.dart' show attachment;
import 'online_widget_test.dart' as online;
import 'online_evidence.dart';
import 'online_widget_test.dart' show tap;

Future<void> open(WidgetTester tester, AssignmentFixture f) async {
  await f.prepare();
  await tester.pumpWidget(
    RepaintBoundary(
      key: onlineCaptureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: IngestionPage(repository: f.inbox, assignment: f),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tap(tester, '分类归档');
}

Future<void> choose(WidgetTester tester, {String category = '服务合同'}) async {
  await tap(tester, '选择案件');
  await tap(tester, '(2026)虚构民初90号');
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(category).last);
  await tester.tap(find.text(category).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(prepareOnlineFont);
  lifecycle();
  recovery();
  busy();
  offline();
  expiry();
  reloadOnly();
}

void lifecycle() {
  testWidgets('必须选择案件分类，全部 11 类可见；归档后进入历史且案件产生原名文件', (tester) async {
    final f = AssignmentFixture();
    await open(tester, f);
    await tap(tester, '确认归档');
    expect(find.text('请选择案件和文件分类。'), findsOneWidget);
    expect(f.attempts, 0);
    await choose(tester);
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(field.initialValue, 'SERVICE_CONTRACT');
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .items!
          .map((item) => item.value),
      documentCategories.keys,
    );
    await captureOnline(tester, fileName: 'client-ingestion-assign.png');
    await tap(tester, '确认归档');
    expect(find.text('微信转发 · 已指派'), findsOneWidget);
    expect(find.text('分类归档'), findsNothing);
    final file = (await f.experience.load()).single.files.single;
    expect(file.category, 'SERVICE_CONTRACT');
    expect(file.name, '虚构服务合同示例.pdf');
  });
  testWidgets('案件列表失败恢复、搜索空态和翻页，取消不改变材料', (tester) async {
    final f = AssignmentFixture()..failCases = true;
    await open(tester, f);
    await tap(tester, '选择案件');
    expect(find.text('案件列表暂不可用。'), findsOneWidget);
    f.failCases = false;
    await tap(tester, '重新加载');
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.tap(find.byTooltip('搜索案件'));
    await tester.pumpAndSettle();
    expect(find.text('没有匹配案件，请先新建案件或修改搜索。'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '虚构');
    for (var i = 0; i < 22; i++) {
      await f.experience.create('虚构分页$i', '虚构分页', '虚构法院');
    }
    await tester.tap(find.byTooltip('搜索案件'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下一页').last);
    await tester.tap(find.text('下一页').last);
    await tester.pumpAndSettle();
    expect(f.queries.last, '虚构:2');
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tap(tester, '取消');
    expect(f.attempts, 0);
    expect((await f.inbox.list()).total, 1);
  });
}

void recovery() {
  testWidgets('失败保留所选案件分类；提交成功响应丢失后重试只归档一次', (tester) async {
    final f = AssignmentFixture()..failAssign = true;
    await open(tester, f);
    await choose(tester);
    await tap(tester, '确认归档');
    expect(find.text('归档失败，请保留选择重试。'), findsOneWidget);
    expect(find.textContaining('(2026)虚构民初90号'), findsOneWidget);
    f.failAssign = false;
    f.loseResponse = true;
    await tap(tester, '重试归档');
    expect(find.text('归档结果未确认，请重试。'), findsOneWidget);
    await tap(tester, '重试归档');
    expect(f.attempts, 3);
    expect((await f.experience.load()).single.files.length, 1);
  });
}

void busy() {
  testWidgets('忙碌期间返回和重复点击不能重复归档，完成后恢复导航', (tester) async {
    final f = AssignmentFixture()..gate = Completer<void>();
    await open(tester, f);
    await choose(tester);
    await tester.tap(find.text('确认归档'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(IngestionAssignDialog), findsOneWidget);
    await tester.tap(find.text('确认归档'));
    await tester.pump();
    expect(f.attempts, 1);
    f.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(IngestionAssignDialog), findsNothing);
  });
}

void offline() {
  testWidgets('窄屏深色完整离线入口：添加示例、分类归档、返回案件按类看到原名', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final f = AssignmentFixture();
    await f.prepare();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          experienceRepositoryProvider.overrideWithValue(f.experience),
        ],
        child: const RepaintBoundary(key: onlineCaptureKey, child: RulerApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, '开始虚构体验');
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tap(tester, '添加虚构文件示例');
    await tap(tester, '分类归档');
    await choose(tester);
    await captureOnline(tester, fileName: 'client-ingestion-assign-demo.png');
    await tap(tester, '确认归档');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tap(tester, '虚构归档纠纷');
    await tap(tester, '示例文件');
    expect(find.text('服务合同 · 1 份'), findsOneWidget);
    expect(find.text('虚构服务合同示例.pdf'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-ingestion-archived-demo.png');
    expect(tester.takeException(), isNull);
  });
}

void expiry() {
  testWidgets('归档前会话失效会销毁选择与材料页面，不能返回旧账号资料', (tester) async {
    final f = IngestionFixture()
      ..entries.add({...ingestionRow(), 'file': attachment()});
    f.records.add({
      'id': 'case',
      'caseNo': '(2026)虚构民初90号',
      'court': '虚构法院',
      'cause': '虚构归档纠纷',
      'stage': 'FIRST_INSTANCE',
      'status': 'ACTIVE',
    });
    await online.start(tester, f);
    await online.login(tester);
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tap(tester, '分类归档');
    await choose(tester);
    f.expire = true;
    await tap(tester, '确认归档');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(IngestionAssignDialog), findsNothing);
    expect(find.byType(IngestionPage), findsNothing);
    expect(find.textContaining('(2026)虚构民初90号'), findsNothing);
  });
}

void reloadOnly() {
  testWidgets('归档成功后列表失败只重读，不再次提交归档', (tester) async {
    final f = AssignmentFixture()..failAfterWrite = true;
    await open(tester, f);
    await choose(tester);
    await tap(tester, '确认归档');
    expect(find.text('列表暂不可用。'), findsOneWidget);
    expect(f.attempts, 1);
    f.inbox.failRead = false;
    await tap(tester, '重新加载');
    expect(find.text('微信转发 · 已指派'), findsOneWidget);
    expect(f.attempts, 1);
    expect((await f.experience.load()).single.files.length, 1);
  });
}
