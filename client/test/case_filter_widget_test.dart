import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/presentation/case_filter_dialog.dart';
import 'api_fixture.dart';
import 'case_filter_fixture.dart';
import 'online_widget_test.dart' as online;
import 'online_evidence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  combineAndClear();
  cancelAndReset();
  pagination();
  failureAndExpiry();
  staleReply();
}

Future<void> choose(WidgetTester tester, int index, String text) async {
  final field = find.byType(DropdownButtonFormField<String>).at(index);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> start(WidgetTester tester, FilterFixture fixture) async {
  await online.start(tester, fixture);
  await online.login(tester);
}

Future<void> court(WidgetTester tester, String value) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(CaseFilterDialog),
      matching: find.byType(TextField),
    ),
    value,
  );
}

void combineAndClear() {
  testWidgets('法院、阶段、状态与关键词组合查询，清除筛选保留关键词并恢复排序', (tester) async {
    final fixture = FilterFixture()
      ..add(1)
      ..add(2, court: '虚构法院乙', stage: 'SECOND_INSTANCE', status: 'CLOSED');
    await start(tester, fixture);
    await tester.enterText(find.byType(TextField), '虚构');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await online.tap(tester, '筛选与排序');
    await court(tester, ' 虚构法院乙 ');
    await choose(tester, 0, '二审');
    await choose(tester, 1, '已结案');
    await choose(tester, 2, '较早更新优先');
    await captureOnline(tester, fileName: 'client-case-filters.png');
    await online.tap(tester, '应用筛选');
    expect(find.text('(2026)虚构民初2号'), findsOneWidget);
    expect(find.text('(2026)虚构民初1号'), findsNothing);
    expect(fixture.queries.last, {
      'page': 1,
      'pageSize': 20,
      'sort': 'asc',
      'keyword': '虚构',
      'court': '虚构法院乙',
      'stage': 'SECOND_INSTANCE',
      'status': 'CLOSED',
    });
    await online.tap(tester, '清除筛选');
    expect(fixture.queries.last, {
      'page': 1,
      'pageSize': 20,
      'sort': 'desc',
      'keyword': '虚构',
    });
    expect(find.text('(2026)虚构民初1号'), findsOneWidget);
  });
}

void cancelAndReset() {
  testWidgets('筛选弹窗取消不查询，重置仅改草稿直到应用，空结果可以清除恢复', (tester) async {
    final fixture = FilterFixture()..add(1);
    await start(tester, fixture);
    await online.tap(tester, '筛选与排序');
    await court(tester, '虚构不存在法院');
    await online.tap(tester, '取消');
    expect(fixture.queries.length, 1);
    await online.tap(tester, '筛选与排序');
    await court(tester, '虚构不存在法院');
    await online.tap(tester, '应用筛选');
    expect(find.text('没有符合条件的测试案件'), findsOneWidget);
    await online.tap(tester, '筛选与排序');
    await online.tap(tester, '重置条件');
    expect(fixture.queries.length, 2);
    await online.tap(tester, '取消');
    expect(find.text('没有符合条件的测试案件'), findsOneWidget);
    await online.tap(tester, '筛选与排序');
    await online.tap(tester, '重置条件');
    await online.tap(tester, '应用筛选');
    expect(find.text('(2026)虚构民初1号'), findsOneWidget);
    expect(fixture.queries.last.containsKey('court'), isFalse);
  });
}

void pagination() {
  testWidgets('翻页携带筛选，修改条件回第一页，排序改变服务端结果顺序', (tester) async {
    final fixture = FilterFixture();
    for (var i = 1; i <= 21; i++) {
      fixture.add(i);
    }
    fixture.add(22, court: '虚构法院乙');
    await start(tester, fixture);
    await online.tap(tester, '筛选与排序');
    await court(tester, '虚构法院甲');
    await choose(tester, 2, '较早更新优先');
    await online.tap(tester, '应用筛选');
    expect(find.text('(2026)虚构民初1号'), findsOneWidget);
    await online.tap(tester, '下一页');
    expect(find.text('第 2 页 · 共 21 条'), findsOneWidget);
    expect(find.text('(2026)虚构民初21号'), findsOneWidget);
    expect(fixture.queries.last['court'], '虚构法院甲');
    expect(fixture.queries.last['sort'], 'asc');
    await online.tap(tester, '筛选与排序');
    await court(tester, '虚构法院乙');
    await online.tap(tester, '应用筛选');
    expect(find.text('第 1 页 · 共 1 条'), findsOneWidget);
    expect(fixture.queries.last['page'], 1);
    expect(find.text('(2026)虚构民初22号'), findsOneWidget);
  });
}

void failureAndExpiry() {
  testWidgets('筛选请求失败保留条件供重试，会话过期清除原账号列表', (tester) async {
    final fixture = FilterFixture()..add(1);
    await start(tester, fixture);
    await online.tap(tester, '筛选与排序');
    await court(tester, '虚构法院甲');
    fixture.failRead = true;
    await online.tap(tester, '应用筛选');
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('(2026)虚构民初1号'), findsNothing);
    fixture.failRead = false;
    await online.tap(tester, '重新加载');
    expect(fixture.queries.last['court'], '虚构法院甲');
    expect(find.text('(2026)虚构民初1号'), findsOneWidget);
    fixture.expire = true;
    await tester.tap(find.byTooltip('刷新案件'));
    await tester.pumpAndSettle();
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.textContaining('虚构法院甲'), findsNothing);
  });
}

class SlowFilterFixture extends FilterFixture {
  final old = Completer<ResponseBody>();
  @override
  Dio dio() => Dio()
    ..httpClientAdapter = TestAdapter((request) {
      if (request.path == '/cases' &&
          request.queryParameters['court'] == '虚构法院甲') {
        return old.future;
      }
      return handle(request);
    });
}

void staleReply() {
  testWidgets('慢的旧筛选响应不会覆盖较新的结果', (tester) async {
    final fixture = SlowFilterFixture()
      ..add(1)
      ..add(2, court: '虚构法院乙');
    await start(tester, fixture);
    await online.tap(tester, '筛选与排序');
    await court(tester, '虚构法院甲');
    await tester.tap(find.text('应用筛选'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('筛选与排序'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await court(tester, '虚构法院乙');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(find.text('(2026)虚构民初2号'), findsOneWidget);
    fixture.old.complete(
      fixture.filtered({'court': '虚构法院甲', 'page': 1, 'sort': 'desc'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('(2026)虚构民初2号'), findsOneWidget);
    expect(find.text('(2026)虚构民初1号'), findsNothing);
  });
}
