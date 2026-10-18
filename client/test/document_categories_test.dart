import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/documents.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'package:ruler_client/presentation/online_documents_page.dart';
import 'document_widget_test.dart' show FilesFixture;
import 'device_files_fixture.dart';
import 'device_files_widget_test.dart' show showFiles;
import 'experience_widget_test.dart' as experience;
import 'online_evidence.dart';

class CategorizedFixture extends FilesFixture {
  @override
  Future<OnlinePage<CaseDocument>> list(
    String caseId, {
    int page = 1,
    String? category,
    bool history = false,
  }) async => OnlinePage(
    [
      for (final key in ['COURT_DOCUMENT', 'SERVICE_CONTRACT'])
        CaseDocument(
          id: key,
          name: '虚构${documentCategories[key]}.pdf',
          category: key,
          size: 620,
          version: 1,
          current: true,
        ),
    ],
    42,
    page,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  uploadCategoryTests();
  groupedListTest();
  offlineCategoryTest();
  test('示例分类独立递增版本，未知分类拒绝且不写入', () async {
    final repository = MemoryExperience();
    final id = await repository.create('虚构', '虚构', '虚构');
    await repository.addSample(id, category: 'COURT_DOCUMENT');
    await repository.addSample(id, category: 'SERVICE_CONTRACT');
    await repository.addSample(id, category: 'COURT_DOCUMENT');
    await expectLater(
      repository.addSample(id, category: 'UNKNOWN'),
      throwsException,
    );
    final files = (await repository.load()).single.files;
    expect(files.map((file) => file.version), [1, 1, 2]);
    expect(files.map((file) => file.category), [
      'COURT_DOCUMENT',
      'SERVICE_CONTRACT',
      'COURT_DOCUMENT',
    ]);
  });
}

void uploadCategoryTests() {
  for (final category in ['COURT_DOCUMENT', 'SERVICE_CONTRACT']) {
    testWidgets('上传必须选分类，$category 原样交给仓库', (tester) async {
      final repository = UploadRepositoryFixture();
      await showFiles(tester, repository, DeviceFixture());
      await tester.tap(find.text('上传文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择设备文件'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '开始上传'))
            .onPressed,
        isNull,
      );
      expect(repository.starts, 0);
      await selectCategory(tester, documentCategories[category]!);
      await tester.tap(find.text('开始上传'));
      await tester.pumpAndSettle();
      expect(repository.starts, 1);
      expect(repository.uploadCategory, category);
    });
  }
}

void groupedListTest() {
  testWidgets('文件页按独立类别分组，本页数量不冒充全部分类总数', (tester) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: onlineCaptureKey,
        child: MaterialApp(
          home: DocumentList(
            caseId: 'fictional',
            repository: CategorizedFixture(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('法院文件 · 本页 1 份'), findsOneWidget);
    expect(find.text('服务合同 · 本页 1 份'), findsOneWidget);
    expect(find.textContaining('以下数量仅统计当前页'), findsOneWidget);
    expect(find.text('下一页'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-categories.png');
    expect(tester.takeException(), isNull);
  });
}

void offlineCategoryTest() {
  testWidgets('离线体验可选择法院文件和服务合同并归入各自分组', (tester) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await experience.enter(tester);
    await experience.createCase(tester);
    await tester.tap(find.text('示例文件'));
    await tester.pumpAndSettle();
    for (final name in ['法院文件', '服务合同']) {
      await selectCategory(tester, name);
      await tester.tap(find.text('添加示例文件版本'));
      await tester.pumpAndSettle();
      expect(find.text('$name · 1 份'), findsOneWidget);
    }
    expect(find.textContaining('版本 1 · 当前示例版本'), findsNWidgets(2));
    await captureOnline(
      tester,
      fileName: 'client-category-demo.png',
      key: experience.captureKey,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> selectCategory(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).last);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(name),
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}
