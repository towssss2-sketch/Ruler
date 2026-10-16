import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/stage_provider.dart';

void main() {
  test('Provider 明确标识客户端虚构体验，支持隔离读取', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(stageProvider), '阶段 11A1 · 客户端虚构体验');
  });
}
