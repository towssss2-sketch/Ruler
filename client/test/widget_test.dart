import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/presentation/ruler_app.dart';

void main() {
  testWidgets('欢迎页清楚显示开发阶段和隐私提示', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RulerApp()));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 RULER'), findsOneWidget);
    expect(find.text('阶段 11A2 · 测试服务接入'), findsOneWidget);
    expect(find.textContaining('请勿输入真实当事人'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('实际点击交付范围并返回欢迎页', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RulerApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看本次交付范围'));
    await tester.pumpAndSettle();
    expect(find.textContaining('本页面离线可用'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 RULER'), findsOneWidget);
  });

  testWidgets('窄屏和深色主题没有布局异常', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const ProviderScope(child: RulerApp()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final context = tester.element(find.text('欢迎使用 RULER'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(find.text('查看本次交付范围'), findsOneWidget);
  });
}
