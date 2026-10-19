import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/case_conflict.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/presentation/case_conflict_dialog.dart';
import 'api_fixture.dart';
import 'case_conflict_test.dart';
import 'online_evidence.dart';
import 'online_fixture.dart';
import 'online_widget_test.dart' as online;
import 'party_widget_test.dart' as party;

class ConflictFixture extends OnlineFixture {
  bool failCheck = false;
  bool empty = false;
  final pages = <int>[];
  @override
  ResponseBody handle(RequestOptions request) {
    if (request.path.endsWith('/conflict-check') && !expire) {
      if (failCheck) return reply(null, 503);
      final page = request.queryParameters['page'] as int;
      pages.add(page);
      return reply(
        conflictPage(
          page: page,
          total: empty ? 0 : 21,
          items: empty
              ? []
              : page == 1
              ? List.generate(20, (i) => conflictRow(i + 1))
              : [conflictRow(21)],
        ),
      );
    }
    return super.handle(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  pagedCandidates();
  failureAndEmpty();
  expiry();
  loading();
}

void pagedCandidates() {
  testWidgets('检查弹窗显示历史删除标记、相似度与人工核对提示，可翻页重查', (tester) async {
    final fixture = ConflictFixture()..seed();
    await party.openDetail(tester, fixture);
    await online.tap(tester, '检查利益冲突');
    expect(find.textContaining('已删除的历史案件 · 姓名相似度 62.5%'), findsOneWidget);
    expect(find.textContaining('未命中也不代表不存在利益冲突'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-conflicts.png');
    await online.tap(tester, '下一页');
    expect(find.text('(2026)虚构民初121号'), findsOneWidget);
    expect(find.text('第 2 页 · 共 21 条'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '下一页'))
          .onPressed,
      isNull,
    );
    await online.tap(tester, '上一页');
    await online.tap(tester, '重新检查');
    expect(fixture.pages, [1, 2, 1, 1]);
    await online.tap(tester, '关闭');
    expect(find.byType(CaseConflictDialog), findsNothing);
    expect(find.text('案件详情与当事人'), findsOneWidget);
  });
}

void failureAndEmpty() {
  testWidgets('窄屏深色检查失败不显示未命中，重试空结果仍要求人工核对', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final fixture = ConflictFixture()
      ..seed()
      ..failCheck = true;
    await party.openDetail(tester, fixture);
    await online.tap(tester, '检查利益冲突');
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.textContaining('本次未命中'), findsNothing);
    fixture
      ..failCheck = false
      ..empty = true;
    await online.tap(tester, '重新加载');
    expect(find.text('本次未命中相似姓名的案件，请继续人工核对。'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '下一页'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}

void expiry() {
  testWidgets('检查期间会话失效，结果弹窗与旧案件一起销毁', (tester) async {
    final fixture = ConflictFixture()..seed();
    await party.openDetail(tester, fixture);
    await online.tap(tester, '检查利益冲突');
    fixture.expire = true;
    await online.tap(tester, '重新检查');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(CaseConflictDialog), findsNothing);
    expect(find.text('(2026)虚构民初101号'), findsNothing);
  });
}

void loading() {
  testWidgets('未完成检查仅显示加载，不能显示过期候选或空结论', (tester) async {
    final gate = Completer<OnlinePage<CaseConflict>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CaseConflictDialog(load: (_) => gate.future)),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('本次未命中'), findsNothing);
    gate.complete(OnlinePage([], 0, 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('本次未命中'), findsOneWidget);
  });
}
