import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/presentation/online_documents_page.dart';
import 'device_files_fixture.dart';
import 'online_evidence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  testWidgets('选择后上传登记失败保留快照，重试同一操作成功', (tester) async {
    final repository = UploadRepositoryFixture()..operation.failFirst = true;
    final files = DeviceFixture();
    await showFiles(tester, repository, files);
    await tester.tap(find.text('上传文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择设备文件'));
    await tester.pumpAndSettle();
    expect(find.text('虚构.pdf · 3 字节'), findsOneWidget);
    if (find.text('请选择材料分类').evaluate().isNotEmpty) {
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('起诉材料').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('开始上传'));
    await tester.pumpAndSettle();
    expect(find.text('登记尚未确认。'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-upload.png');
    await tester.tap(find.text('重试登记'));
    await tester.pumpAndSettle();
    expect(repository.starts, 1);
    expect(repository.operation.tries, 2);
    expect(files.selected.disposed, true);
    expect(find.byType(AlertDialog), findsNothing);
  });
  cancellationTests();
  lateSelectionTest();
  versionAndSaveTest();
}

void lateSelectionTest() {
  testWidgets('页面销毁后的选择结果只清理，不恢复旧窗口', (tester) async {
    final files = DeviceFixture()..delayedPick = Completer();
    final repository = UploadRepositoryFixture();
    await showFiles(tester, repository, files);
    await tester.tap(find.text('上传文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择设备文件'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    files.delayedPick!.complete(files.selected);
    await tester.pumpAndSettle();
    expect(files.selected.disposed, true);
    expect(repository.starts, 0);
    expect(tester.takeException(), isNull);
  });
}

void cancellationTests() {
  testWidgets('系统选择取消不会开始上传', (tester) async {
    final repository = UploadRepositoryFixture();
    await showFiles(tester, repository, DeviceFixture()..cancelPick = true);
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
  });
  testWidgets('关闭在途上传取消操作并释放临时快照', (tester) async {
    final repository = UploadRepositoryFixture()
      ..operation.delayed = Completer();
    final files = DeviceFixture();
    await showFiles(tester, repository, files);
    await tester.tap(find.text('上传文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择设备文件'));
    await tester.pumpAndSettle();
    if (find.text('请选择材料分类').evaluate().isNotEmpty) {
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('起诉材料').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('开始上传'));
    await tester.pump();
    await tester.tap(find.text('停止并关闭'));
    await tester.pumpAndSettle();
    expect(repository.operation.cancelled, true);
    expect(files.selected.disposed, true);
    expect(tester.takeException(), isNull);
  });
}

void versionAndSaveTest() {
  testWidgets('新版本绑定当前文件及分类，保存取消不显示成功', (tester) async {
    final repository = UploadRepositoryFixture();
    final files = DeviceFixture()..saved = false;
    await showFiles(tester, repository, files);
    await tester.tap(find.text('上传新版本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择设备文件'));
    await tester.pumpAndSettle();
    if (find.text('请选择材料分类').evaluate().isNotEmpty) {
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('起诉材料').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('开始上传'));
    await tester.pumpAndSettle();
    expect(repository.previous, 'v2');
    expect(repository.uploadCategory, 'EVIDENCE');
    await tester.tap(find.text('下载保存'));
    await tester.pumpAndSettle();
    expect(find.text('已取消保存。'), findsOneWidget);
    expect(find.text('文件已保存到所选位置。'), findsNothing);
  });
}

Future<void> showFiles(
  WidgetTester tester,
  UploadRepositoryFixture repository,
  DeviceFixture files,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: onlineCaptureKey,
      child: MaterialApp(
        home: DocumentList(
          caseId: 'case-1',
          repository: repository,
          files: files,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
