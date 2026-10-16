import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/experience_provider.dart';
import 'package:ruler_client/domain/experience.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';
import 'package:ruler_client/presentation/ruler_app.dart';

const captureKey = ValueKey('experience-capture');

Future<void> enter(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: RepaintBoundary(key: captureKey, child: RulerApp()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('开始虚构体验'));
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('../test-results/client-experience-task.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> createCase(WidgetTester tester) async {
  await tester.tap(find.text('新建案件'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('创建体验案件'));
  await tester.pumpAndSettle();
  expect(find.text('体验案件详情'), findsOneWidget);
}

class RetryExperience extends MemoryExperience {
  bool fail = true;
  @override
  Future<List<ExperienceCase>> load() async {
    if (fail) {
      fail = false;
      throw StateError('fictional-private-error');
    }
    return super.load();
  }
}

class PendingExperience extends MemoryExperience {
  final pending = Completer<List<ExperienceCase>>();
  @override
  Future<List<ExperienceCase>> load() => pending.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final configured = Platform.environment['RULER_TEST_CJK_FONT'];
    final font = File(
      configured ?? '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    );
    if (!await font.exists()) {
      if (configured != null) throw StateError('配置的中文测试字体不存在');
      return;
    }
    final loader = FontLoader('Roboto')
      ..addFont(font.readAsBytes().then((bytes) => bytes.buffer.asByteData()));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  registerExperienceTest1();
  registerExperienceTest2();
  registerExperienceTest3();
  registerExperienceTest4();
  registerExperienceTest5();
  registerExperienceTest6();
  registerExperienceTest7();
  registerExperienceTest8();
}

void registerExperienceTest8() {
  testWidgets('系统返回依次经过详情、列表和欢迎页，返回体验仍保留本次数据', (tester) async {
    await enter(tester);
    await createCase(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('我的体验案件'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 RULER'), findsOneWidget);
    await tester.tap(find.text('开始虚构体验'));
    await tester.pumpAndSettle();
    expect(find.text('虚构合同纠纷'), findsOneWidget);
  });
}

void registerExperienceTest1() {
  testWidgets('实际点击案件、示例文件版本、任务完成恢复的离线闭环', (tester) async {
    await enter(tester);
    expect(find.textContaining('还没有体验案件'), findsOneWidget);
    await createCase(tester);
    await tester.tap(find.text('示例文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加示例文件版本'));
    await tester.pumpAndSettle();
    expect(find.text('虚构示例材料.pdf'), findsOneWidget);
    await tester.tap(find.text('添加示例文件版本'));
    await tester.pumpAndSettle();
    expect(find.textContaining('版本 2 · 当前示例版本'), findsOneWidget);
    await tester.tap(find.text('工作任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加体验任务'));
    await tester.pumpAndSettle();
    expect(find.text('核对虚构示例材料'), findsOneWidget);
    await tester.tap(find.text('标记完成'));
    await tester.pumpAndSettle();
    expect(find.text('已完成'), findsOneWidget);
    await capture(tester);
    await tester.tap(find.text('恢复待办'));
    await tester.pumpAndSettle();
    expect(find.text('待办'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void registerExperienceTest2() {
  testWidgets('返回列表可搜索，移除确认只清理体验案件', (tester) async {
    await enter(tester);
    await createCase(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不匹配');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的体验案件'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('虚构合同纠纷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除体验案件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('虚构合同纠纷'), findsOneWidget);
    await tester.tap(find.text('移除体验案件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有体验案件'), findsOneWidget);
  });
}

void registerExperienceTest3() {
  testWidgets('加载、错误、重试三态真实发生，不显示内部异常', (tester) async {
    final repository = RetryExperience();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [experienceRepositoryProvider.overrideWithValue(repository)],
        child: const RulerApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始虚构体验'));
    await tester.pumpAndSettle();
    expect(find.text('体验数据暂未加载，请重试'), findsOneWidget);
    expect(find.textContaining('fictional-private-error'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有体验案件'), findsOneWidget);
  });
}

void registerExperienceTest4() {
  testWidgets('窄屏深色模式可以创建案件并切换任务，无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await enter(tester);
    await createCase(tester);
    await tester.tap(find.text('工作任务'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

void registerExperienceTest5() {
  testWidgets('异步仓库未完成时显示加载，完成后呈现空状态', (tester) async {
    final repository = PendingExperience();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [experienceRepositoryProvider.overrideWithValue(repository)],
        child: const RulerApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始虚构体验'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有体验案件'), findsOneWidget);
  });
}

void registerExperienceTest6() {
  testWidgets('重复案件创建失败保留表单和原案件，空任务显示错误', (tester) async {
    await enter(tester);
    await createCase(tester);
    await tester.tap(find.text('工作任务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' ');
    await tester.tap(find.text('添加体验任务'));
    await tester.pumpAndSettle();
    expect(find.text('请填写 1–255 字的任务标题'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建案件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建体验案件'));
    await tester.pumpAndSettle();
    expect(find.text('体验案件的案号和法院重复'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '(2026)虚构民初1号'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('虚构合同纠纷'), findsOneWidget);
  });
}

void registerExperienceTest7() {
  test('Provider 异步加载、变更和重试保持隔离', () async {
    final repository = MemoryExperience();
    final container = ProviderContainer(
      overrides: [experienceRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    expect(
      container.read(experienceProvider),
      isA<AsyncLoading<List<ExperienceCase>>>(),
    );
    expect(await container.read(experienceProvider.future), isEmpty);
    final controller = container.read(experienceProvider.notifier);
    final id = await controller.create('虚构1', '虚构案由', '虚构法院');
    await controller.addTask(id, '虚构任务');
    await controller.addSample(id);
    final record = container.read(experienceProvider).requireValue.single;
    expect(record.tasks.length, 1);
    expect(record.files.length, 1);
    await controller.removeFile(id, record.files.single.id);
    await controller.reload();
    expect(
      container.read(experienceProvider).requireValue.single.files,
      isEmpty,
    );
  });
}
