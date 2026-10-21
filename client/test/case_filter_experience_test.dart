import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/experience_provider.dart';
import 'package:ruler_client/domain/case_detail.dart';
import 'package:ruler_client/domain/case_fields.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'case_filter_widget_test.dart' as filter;
import 'experience_widget_test.dart' as demo;
import 'online_widget_test.dart' as online;
import 'online_evidence.dart';

Future<void> open(WidgetTester tester, MemoryExperience repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [experienceRepositoryProvider.overrideWithValue(repository)],
      child: const RepaintBoundary(key: demo.captureKey, child: RulerApp()),
    ),
  );
  await online.tap(tester, '开始虚构体验');
}

Future<MemoryExperience> seed() async {
  final repository = MemoryExperience();
  await repository.create('(2026)虚构民初1号', '虚构案由甲', '虚构法院甲');
  final second = await repository.create(
    '(2026)虚构民初2号',
    '虚构案由乙',
    '虚构法院乙',
    parties: [const CaseParty(name: '虚构乙', role: 'PLAINTIFF')],
  );
  await repository.update(
    second,
    const CaseFields(
      caseNo: '(2026)虚构民初2号',
      cause: '虚构案由乙',
      court: '虚构法院乙',
      stage: 'SECOND_INSTANCE',
      status: 'CLOSED',
    ),
  );
  return repository;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  narrowScreen();
  editOrder();
}

void narrowScreen() {
  testWidgets('窄屏深色离线组合筛选、当事人搜索和清除条件可直接体验', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await open(tester, await seed());
    await online.tap(tester, '筛选与排序');
    await filter.court(tester, '虚构法院乙');
    await filter.choose(tester, 0, '二审');
    await filter.choose(tester, 1, '已结案');
    await online.tap(tester, '应用筛选');
    expect(find.text('虚构案由甲'), findsNothing);
    expect(find.text('虚构案由乙'), findsOneWidget);
    await captureOnline(
      tester,
      fileName: 'client-case-filters-demo.png',
      key: demo.captureKey,
    );
    await tester.enterText(find.byType(TextField), '虚构乙');
    await tester.pumpAndSettle();
    await online.tap(tester, '清除筛选');
    expect(find.text('虚构案由甲'), findsNothing);
    expect(find.text('虚构案由乙'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('虚构案由甲'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

List<String?> visibleTitles(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .map((tile) => (tile.title as Text).data)
    .toList();
void editOrder() {
  testWidgets('离线从筛选列表编辑案件再返回，保留排序条件并按新更新时间重新排位', (tester) async {
    var now = DateTime.utc(2026, 1, 1);
    final repository = MemoryExperience(now: () => now);
    await repository.create('(2026)虚构民初1号', '虚构案由甲', '虚构法院甲');
    now = DateTime.utc(2026, 1, 2);
    await repository.create('(2026)虚构民初2号', '虚构案由乙', '虚构法院乙');
    await open(tester, repository);
    await online.tap(tester, '筛选与排序');
    await filter.choose(tester, 2, '较早更新优先');
    await online.tap(tester, '应用筛选');
    expect(visibleTitles(tester), ['虚构案由甲', '虚构案由乙']);
    await online.tap(tester, '虚构案由甲');
    await online.tap(tester, '编辑案件信息');
    now = DateTime.utc(2026, 1, 3);
    await tester.enterText(find.byType(TextFormField).at(1), '虚构修改甲');
    await online.tap(tester, '保存体验修改');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('较早更新优先'), findsOneWidget);
    expect(visibleTitles(tester), ['虚构案由乙', '虚构修改甲']);
    await tester.tap(find.byTooltip('刷新体验列表'));
    await tester.pumpAndSettle();
    expect(visibleTitles(tester), ['虚构案由乙', '虚构修改甲']);
  });
}
