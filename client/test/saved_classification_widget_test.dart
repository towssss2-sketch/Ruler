import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/saved_classification.dart';
import 'package:ruler_client/presentation/saved_classification_dialog.dart';
import 'package:ruler_client/presentation/preview_attempts_dialog.dart';
import 'saved_classification_fixture.dart';
import 'preview_attempt_widget_test.dart' show open, historyTap;
import 'online_widget_test.dart' as online;
import 'online_widget_test.dart' show tap;
import 'ingestion_fixture.dart';
import 'ingestion_file_api_fixture.dart' show attachment;
import 'online_evidence.dart';

Future<void> classificationOpen(
  WidgetTester tester,
  ClassificationFixture f,
) async {
  await open(tester, f);
  await historyTap(tester, '查看已保存分类');
}

void main() {
  setUpAll(prepareOnlineFont);
  testWidgets('指定提取历史展示五类建议与人工确认边界，只读不提取不归档', (tester) async {
    final f = ClassificationFixture();
    await classificationOpen(tester, f);
    expect(find.text('建议分类：服务合同'), findsOneWidget);
    expect(find.text('识别规则：标题规则 v1'), findsOneWidget);
    expect(find.textContaining('不代表当前归档分类'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-saved-classification.png');
    for (final category in [
      'PLEADING',
      'DEFENSE',
      'COURT_DOCUMENT',
      'SUMMONS',
    ]) {
      f.savedCategory = category;
      await tap(tester, '刷新分类');
      expect(find.text('建议分类：${documentCategories[category]}'), findsOneWidget);
    }
    expect(f.reads.every((value) => value.$2 == 'fixture-0'), isTrue);
    expect(f.calls, 0);
    expect(f.assigned.attempts, 0);
    await tap(tester, '返回记录');
    expect(find.byType(PreviewAttemptsDialog), findsOneWidget);
  });
  testWidgets('无标题/冲突与旧版未记录/提取未完成有不同提示，均不显示可直接归档的分类', (tester) async {
    final f = ClassificationFixture()
      ..savedCategory = null
      ..savedReason = 'NO_TITLE';
    await classificationOpen(tester, f);
    expect(find.textContaining('未识别到明确标题'), findsOneWidget);
    f.savedReason = 'CONFLICTING_TITLES';
    await tap(tester, '刷新分类');
    expect(find.textContaining('标题提示多个类别'), findsOneWidget);
    f.savedState = 'NOT_RECORDED';
    await tap(tester, '刷新分类');
    expect(find.textContaining('旧版历史不会补填'), findsOneWidget);
    expect(find.text('没有确定的分类建议'), findsNothing);
    f.savedState = 'NOT_AVAILABLE';
    await tap(tester, '刷新分类');
    expect(find.textContaining('尚无可用的分类结果'), findsOneWidget);
    expect(f.calls, 0);
    expect(f.assigned.attempts, 0);
  });
  testWidgets('分类读取失败不当作未记录，刷新清除旧分类且手动重试可恢复', (tester) async {
    final f = ClassificationFixture();
    await classificationOpen(tester, f);
    f.failClassification = true;
    await tap(tester, '刷新分类');
    expect(find.text('分类暂时无法读取，请重试。'), findsOneWidget);
    expect(find.text('建议分类：服务合同'), findsNothing);
    expect(find.textContaining('旧版历史不会补填'), findsNothing);
    f.failClassification = false;
    await tap(tester, '重新加载');
    expect(find.text('建议分类：服务合同'), findsOneWidget);
    expect(f.calls, 0);
  });
  testWidgets('刷新后旧响应不覆盖新分类，关闭后晚到响应不恢复窗口', (tester) async {
    final f = ClassificationFixture();
    await classificationOpen(tester, f);
    final old = Completer<SavedClassification>();
    f.classificationGate = old;
    await tester.tap(find.text('刷新分类'));
    await tester.pump();
    expect(find.text('建议分类：服务合同'), findsNothing);
    f.classificationGate = null;
    f.savedCategory = 'DEFENSE';
    await tap(tester, '刷新分类');
    old.complete(
      const SavedClassification(attemptId: 'fixture-0', state: 'NOT_RECORDED'),
    );
    await tester.pumpAndSettle();
    expect(find.text('建议分类：答辩材料'), findsOneWidget);
    final closing = Completer<SavedClassification>();
    f.classificationGate = closing;
    await tester.tap(find.text('刷新分类'));
    await tester.pump();
    await tap(tester, '返回记录');
    closing.complete(
      const SavedClassification(attemptId: 'fixture-0', state: 'NOT_RECORDED'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SavedClassificationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('从第二页读取所选尝试，返回保留页码；处理中没有历史分类按钮', (tester) async {
    final f = ClassificationFixture()..total = 21;
    await open(tester, f);
    await historyTap(tester, '下一页');
    await historyTap(tester, '查看已保存分类');
    expect(f.reads.single.$2, 'fixture-20');
    await tap(tester, '返回记录');
    expect(find.text('第 2 页 · 共 21 条'), findsOneWidget);
    f.status = 'RUNNING';
    await tap(tester, '刷新记录');
    expect(find.text('查看已保存分类'), findsNothing);
  });
  testWidgets('历史分类401清除嵌套窗口和已显示内容，返回登录页', (tester) async {
    final f = ClassificationSessionFixture()
      ..entries.add({...ingestionRow(), 'file': attachment()});
    await online.start(tester, f);
    await online.login(tester);
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('提取记录'));
    await tester.pumpAndSettle();
    await tap(tester, '提取记录');
    await historyTap(tester, '查看已保存分类');
    expect(find.text('建议分类：服务合同'), findsOneWidget);
    f.expire = true;
    await tap(tester, '刷新分类');
    expect(find.byType(SavedClassificationDialog), findsNothing);
    expect(find.byType(PreviewAttemptsDialog), findsNothing);
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.text('建议分类：服务合同'), findsNothing);
  });
}
