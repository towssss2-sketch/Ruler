import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/documents_provider.dart';
import 'package:ruler_client/application/online_provider.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/presentation/ingestion_page.dart';
import 'package:ruler_client/presentation/ingestion_upload_dialog.dart';
import 'package:ruler_client/presentation/ruler_app.dart';
import 'ingestion_fixture.dart';
import 'ingestion_file_api_fixture.dart' show attachment;
import 'ingestion_file_widget_fixture.dart';
import 'online_evidence.dart';
import 'online_widget_test.dart' show tap, login;

Future<void> openFiles(
  WidgetTester tester,
  IngestionFilesFixture files,
  IngestionDeviceFixture device,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: onlineCaptureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: IngestionPage(
          repository: files.inbox,
          attachments: files,
          files: device,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester) async {
  await tap(tester, '导入设备文件');
  await tap(tester, '选择设备文件');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareOnlineFont);
  lifecycle();
  recovery();
  cancellation();
  latePick();
  busy();
  expiry();
  offline();
}

void lifecycle() {
  testWidgets('文件选择、登记失败重试、详情、下载与忽略历史完整点击', (tester) async {
    final files = IngestionFilesFixture(FileInboxFixture())
      ..operation.failFirst = true;
    final device = IngestionDeviceFixture();
    await openFiles(tester, files, device);
    await select(tester);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tap(tester, '开始上传');
    expect(find.text('重试登记'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-ingestion-upload.png');
    await tap(tester, '重试登记');
    expect(files.starts, 1);
    expect(files.operation.tries, 2);
    expect(device.selected.disposed, true);
    expect(find.textContaining('附件：虚构服务合同示例.pdf'), findsOneWidget);
    await captureOnline(tester, fileName: 'client-ingestion-file.png');
    await tap(tester, '查看材料');
    expect(find.text('以下是接收说明。文件正文可从材料列表的正文预览入口查看。'), findsOneWidget);
    await tap(tester, '关闭');
    await tap(tester, '下载原件');
    expect(device.savedName, '虚构服务合同示例.pdf');
    expect(device.savedBytes, 1024);
    await tap(tester, '忽略材料');
    await tap(tester, '确认忽略');
    await tap(tester, '归集历史');
    expect(find.text('微信转发 · 已忽略'), findsOneWidget);
    expect(find.text('下载原件'), findsOneWidget);
  });
}

void recovery() {
  testWidgets('上传成功后列表读取失败只重读，下载失败可独立重试及取消保存', (tester) async {
    final inbox = FileInboxFixture()..failAfterWrite = true;
    final files = IngestionFilesFixture(inbox);
    final device = IngestionDeviceFixture();
    await openFiles(tester, files, device);
    await select(tester);
    await tap(tester, '开始上传');
    expect(find.text('列表暂不可用。'), findsOneWidget);
    inbox.failRead = false;
    await tap(tester, '重新加载');
    expect(files.operation.tries, 1);
    files.failDownload = true;
    await tap(tester, '下载原件');
    expect(find.text('下载未完成。'), findsOneWidget);
    files.failDownload = false;
    device.saved = false;
    await tap(tester, '下载原件');
    expect(find.text('已取消保存。'), findsOneWidget);
    expect(files.downloads, 2);
  });
}

void cancellation() {
  testWidgets('选择取消无上传；处理中系统返回被拦，主动停止取消并释放快照', (tester) async {
    final files = IngestionFilesFixture(FileInboxFixture());
    final device = IngestionDeviceFixture()..cancelPick = true;
    await openFiles(tester, files, device);
    await select(tester);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '开始上传'))
          .onPressed,
      isNull,
    );
    device.cancelPick = false;
    await tap(tester, '选择设备文件');
    files.operation.gate = Completer<void>();
    await tester.tap(find.text('开始上传'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(IngestionUploadDialog), findsOneWidget);
    await tap(tester, '停止并关闭');
    expect(files.operation.cancelled, true);
    expect(device.selected.disposed, true);
    expect((await files.inbox.list()).total, 0);
    expect(tester.takeException(), isNull);
  });
}

void latePick() {
  testWidgets('销毁页面后晚到文件只清理，不恢复旧窗口', (tester) async {
    final files = IngestionFilesFixture(FileInboxFixture());
    final device = IngestionDeviceFixture()..delayedPick = Completer();
    await openFiles(tester, files, device);
    await tap(tester, '导入设备文件');
    await tester.tap(find.text('选择设备文件'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    device.delayedPick!.complete(device.selected);
    await tester.pumpAndSettle();
    expect(device.selected.disposed, true);
    expect(files.starts, 0);
    expect(tester.takeException(), isNull);
  });
}

void busy() {
  testWidgets('上传等待禁连点，完成后返回待定区独立读取', (tester) async {
    final files = IngestionFilesFixture(FileInboxFixture())
      ..operation.gate = Completer<void>();
    await openFiles(tester, files, IngestionDeviceFixture());
    await select(tester);
    await tester.tap(find.text('开始上传'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '处理中…'))
          .onPressed,
      isNull,
    );
    files.operation.gate!.complete();
    await tester.pumpAndSettle();
    expect(files.starts, 1);
    expect(find.byType(IngestionUploadDialog), findsNothing);
    expect(find.text('文件已保存到待定区。'), findsOneWidget);
  });
}

void expiry() {
  testWidgets('下载鉴权失效销毁附件页和设备工作，不能返回旧账号资料', (tester) async {
    final fixture = IngestionFixture()
      ..entries.add({...ingestionRow(), 'file': attachment()});
    final device = IngestionDeviceFixture();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiOriginProvider.overrideWithValue('https://example.invalid'),
          apiFactoryProvider.overrideWithValue(
            (origin, expired) =>
                ApiSession(origin, dio: fixture.dio(), onExpired: expired),
          ),
          deviceFilesProvider.overrideWith((ref) {
            ref.onDispose(device.close);
            return device;
          }),
        ],
        child: const RulerApp(),
      ),
    );
    await tap(tester, '测试服务登录');
    await login(tester);
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    fixture.expire = true;
    await tap(tester, '下载原件');
    expect(find.text('测试账号登录'), findsOneWidget);
    expect(find.byType(IngestionPage), findsNothing);
    expect(device.closed, true);
  });
}

void offline() {
  testWidgets('窄屏深色虚构文件示例可查看、去重、忽略并保留附件历史', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      const ProviderScope(
        child: RepaintBoundary(key: onlineCaptureKey, child: RulerApp()),
      ),
    );
    await tap(tester, '开始虚构体验');
    await tester.tap(find.byTooltip('材料待定区'));
    await tester.pumpAndSettle();
    await tap(tester, '添加虚构文件示例');
    expect(find.text('虚构示例，无真实原件'), findsOneWidget);
    expect(find.text('导入设备文件'), findsNothing);
    expect(find.text('下载原件'), findsNothing);
    await captureOnline(tester, fileName: 'client-ingestion-file-demo.png');
    await tap(tester, '添加虚构文件示例');
    expect(find.text('第 1 页 · 共 1 条'), findsOneWidget);
    await tap(tester, '忽略材料');
    await tap(tester, '确认忽略');
    await tap(tester, '添加虚构文件示例');
    expect(find.text('微信转发 · 已忽略'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
