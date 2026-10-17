import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/presentation/online_documents_page.dart';
import 'online_evidence.dart';

class FilesFixture implements DocumentRepository {
  bool fail = false;
  String? category;
  int page = 1;
  int removed = 0;
  @override
  Future<OnlinePage<CaseDocument>> list(
    String caseId, {
    int page = 1,
    String? category,
    bool history = false,
  }) async {
    this.category = category;
    this.page = page;
    if (fail) throw const ApiFailure('文件读取失败，请重试。');
    return OnlinePage(
      category == 'OTHER' || removed > 0
          ? []
          : [
              const CaseDocument(
                id: 'v2',
                name: '虚构材料.pdf',
                category: 'EVIDENCE',
                size: 620,
                version: 2,
                current: true,
              ),
              if (history)
                const CaseDocument(
                  id: 'v1',
                  name: '虚构材料.pdf',
                  category: 'EVIDENCE',
                  size: 620,
                  version: 1,
                  current: false,
                ),
            ],
      category == 'OTHER' || removed > 0 ? 0 : 21,
      page,
    );
  }

  @override
  Future<void> remove(String id) async {
    removed++;
  }

  @override
  DocumentUpload beginUpload(
    String caseId,
    UploadSource source,
    String category, {
    String? previousId,
  }) => throw StateError('测试未使用此入口');
  @override
  Future<void> download(
    CaseDocument document,
    Future<void> Function(Stream<List<int>>) consume,
  ) async => throw StateError('测试未使用此入口');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  testWidgets('文件分类、历史版本和分页按服务端接口切换', (tester) async {
    final repository = FilesFixture();
    await show(tester, repository);
    expect(find.textContaining('v2 · 当前版本'), findsOneWidget);
    expect(find.textContaining('v1 · 历史版本'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.textContaining('v1 · 历史版本'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-files.png');
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(repository.page, 2);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('其他').last);
    await tester.tap(find.text('其他').last);
    await tester.pumpAndSettle();
    expect(repository.category, 'OTHER');
    expect(repository.page, 1);
    expect(find.text('暂无符合条件的案件文件'), findsOneWidget);
  });
  registerFailureTest();
  registerDeletionTest();
}

void registerFailureTest() {
  testWidgets('文件读取失败保留重试入口，窄屏没有溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FilesFixture()..fail = true;
    await show(tester, repository);
    expect(find.text('文件读取失败，请重试。'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('虚构材料.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void registerDeletionTest() {
  testWidgets('删除说明保留容量，取消不调用接口，确认后重新读取', (tester) async {
    final repository = FilesFixture();
    await show(tester, repository);
    await tester.tap(find.text('删除文件版本'));
    await tester.pumpAndSettle();
    expect(find.textContaining('占用容量仍保留'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.removed, 0);
    await tester.tap(find.text('删除文件版本'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await tester.pumpAndSettle();
    expect(repository.removed, 1);
    expect(find.text('暂无符合条件的案件文件'), findsOneWidget);
  });
}

Future<void> show(WidgetTester tester, FilesFixture repository) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: onlineCaptureKey,
      child: MaterialApp(
        home: DocumentList(caseId: 'case-1', repository: repository),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
