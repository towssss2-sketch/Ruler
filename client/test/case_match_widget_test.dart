import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/experience_provider.dart';
import 'package:ruler_client/application/ingestion_provider.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/presentation/ingestion_case_picker.dart';
import 'package:ruler_client/presentation/ingestion_assign_dialog.dart';
import 'package:ruler_client/presentation/ingestion_preview_dialog.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'ingestion_assign_fixture.dart';
import 'ingestion_preview_fixture.dart';
import 'ingestion_preview_widget_test.dart' as preview;
import 'ingestion_fixture.dart';
import 'ingestion_file_api_fixture.dart' show attachment;
import 'online_widget_test.dart' as online;
import 'online_widget_test.dart' show tap;
import 'online_evidence.dart';

const number = '(2026)虚构民初90号', second = '(2026)虚构民初91号';
Future<void> exact(WidgetTester tester, [String value = number]) async {
  final chip = find.widgetWithText(ChoiceChip, '查找 $value');
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> picker(WidgetTester tester, AssignmentFixture f) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => IngestionCasePicker(
                repository: f,
                caseNumbers: const [number, second],
              ),
            ),
            child: const Text('打开选案'),
          ),
        ),
      ),
    ),
  );
  await tap(tester, '打开选案');
}

class DelayedCases extends AssignmentFixture {
  Completer<OnlinePage<OnlineCase>>? pending;
  @override
  Future<OnlinePage<OnlineCase>> cases({
    String keyword = '',
    int page = 1,
    String? caseNo,
  }) {
    if (caseNo == number && pending != null) return pending!.future;
    return super.cases(keyword: keyword, page: page, caseNo: caseNo);
  }
}

void main() {
  setUpAll(prepareOnlineFont);
  confirmation();
  queries();
  lifecycle();
  offline();
}

void confirmation() {
  testWidgets('正文候选带入选案；同号多法院逐一展示，选案不写入，最终确认才归档', (tester) async {
    final f = PreviewFixture();
    await preview.open(tester, f);
    final other = await f.assigned.experience.create(number, '虚构另案', '虚构乙法院');
    await tap(tester, '按建议选择分类');
    await tap(tester, '选择案件');
    await exact(tester);
    expect(f.assigned.queries.last, 'exact:$number:1');
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.textContaining('虚构乙法院'), findsOneWidget);
    expect(f.assigned.attempts, 0);
    await captureOnline(tester, fileName: 'client-ingestion-match.png');
    await tester.tap(
      find.ancestor(
        of: find.textContaining('虚构乙法院'),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pumpAndSettle();
    expect(f.assigned.attempts, 0);
    expect(find.textContaining('虚构乙法院'), findsOneWidget);
    await tap(tester, '确认归档');
    expect(
      (await f.assigned.experience.load())
          .singleWhere((c) => c.id == other)
          .files
          .single
          .category,
      'SERVICE_CONTRACT',
    );
  });
  testWidgets('没有分类但有案号仍可选案；不默认其他，须补选类别，取消无归档', (tester) async {
    final f = PreviewFixture()
      ..result = previewResult(category: null, reason: 'NO_TITLE');
    await preview.open(tester, f);
    await tap(tester, '按案号选择案件');
    await tap(tester, '选择案件');
    await exact(tester);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tap(tester, '确认归档');
    expect(find.text('请选择案件和文件分类。'), findsOneWidget);
    expect(f.assigned.attempts, 0);
    await tap(tester, '取消');
    expect((await f.inbox.list()).items.single.status, 'PENDING_MATCH');
  });
}

void queries() {
  testWidgets('精确条件保持分页和重试；换候选号回第一页，清除后恢复全部案件', (tester) async {
    final f = AssignmentFixture();
    await f.prepare();
    for (var i = 0; i < 20; i++) {
      await f.experience.create(number, '虚构同号', '虚构法院$i');
    }
    await f.experience.create(second, '虚构另号', '虚构法院');
    await picker(tester, f);
    await exact(tester);
    await tap(tester, '下一页');
    expect(f.queries.last, 'exact:$number:2');
    f.failCases = true;
    await exact(tester, second);
    expect(find.text('案件列表暂不可用。'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    f.failCases = false;
    await tap(tester, '重新加载');
    expect(f.queries.last, 'exact:$second:1');
    expect(find.byType(ListTile), findsOneWidget);
    await tap(tester, '清除案号条件');
    expect(f.queries.last, ':1');
    expect(find.text('第 1 页 · 共 22 条'), findsOneWidget);
  });
  testWidgets('精确未命中不扩大搜索；用户主动输入关键词才能改选案件', (tester) async {
    final f = AssignmentFixture();
    await f.prepare();
    await picker(tester, f);
    await exact(tester, second);
    expect(find.textContaining('本人案件中没有这个完整案号'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    await tester.enterText(find.byType(TextField), '虚构归档纠纷');
    await tester.tap(find.byTooltip('搜索案件'));
    await tester.pumpAndSettle();
    expect(f.queries.last, '虚构归档纠纷:1');
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('清除案号条件'), findsNothing);
    await tap(tester, '取消');
    expect(f.attempts, 0);
  });
}

void lifecycle() {
  testWidgets('切换候选号不显示旧结果；取消后晚到响应不恢复选案窗口', (tester) async {
    final f = DelayedCases();
    await f.prepare();
    await picker(tester, f);
    f.pending = Completer<OnlinePage<OnlineCase>>();
    await tester.tap(find.widgetWithText(ChoiceChip, '查找 $number'));
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
    await exact(tester, second);
    f.pending!.complete(await f.repository.cases(caseNo: number));
    await tester.pumpAndSettle();
    expect(find.textContaining('本人案件中没有这个完整案号'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    f.pending = Completer<OnlinePage<OnlineCase>>();
    await tester.tap(find.widgetWithText(ChoiceChip, '查找 $number'));
    await tester.pump();
    await tap(tester, '取消');
    f.pending!.complete(await f.repository.cases(caseNo: number));
    await tester.pumpAndSettle();
    expect(find.byType(IngestionCasePicker), findsNothing);
  });
  testWidgets('精确查询遇到会话失效时销毁选案、归档及正文页面', (tester) async {
    final f = PreviewSessionFixture()
      ..entries.add({...ingestionRow(), 'file': attachment()});
    await online.start(tester, f);
    await online.login(tester);
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tap(tester, '提取正文');
    await tap(tester, '按建议选择分类');
    await tap(tester, '选择案件');
    f.expire = true;
    await exact(tester);
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(IngestionCasePicker), findsNothing);
    expect(find.byType(IngestionAssignDialog), findsNothing);
    expect(find.byType(IngestionPreviewDialog), findsNothing);
  });
}

void offline() {
  testWidgets('320宽深色放大文字：实际离线正文→案号精确匹配→人工确认归档', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
    await tap(tester, '按建议选择分类');
    await tap(tester, '选择案件');
    await exact(tester);
    await tester.ensureVisible(find.byType(ListTile));
    await captureOnline(tester, fileName: 'client-ingestion-match-demo.png');
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tap(tester, '确认归档');
    expect(
      (await f.assigned.experience.load()).single.files.single.category,
      'SERVICE_CONTRACT',
    );
    expect(tester.takeException(), isNull);
  });
}
