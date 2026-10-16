import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const onlineCaptureKey = ValueKey('online-capture');

/// 使用系统中文字体绘制测试截图，不向应用新增字体依赖。
Future<void> prepareOnlineFont() async {
  final configured = Platform.environment['RULER_TEST_CJK_FONT'];
  final file = File(
    configured ?? '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  );
  if (!await file.exists()) {
    if (configured != null) throw StateError('配置的中文测试字体不存在');
    return;
  }
  await (FontLoader(
        'Roboto',
      )..addFont(file.readAsBytes().then((bytes) => bytes.buffer.asByteData())))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

/// 截取实际连接版 Widget；数据来自协议替身，不作为真机联调证据。
Future<void> captureOnline(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(onlineCaptureKey),
  );
  await tester.runAsync(() async {
    final frame = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../test-results/client-online-task.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      frame.dispose();
    }
  });
}
