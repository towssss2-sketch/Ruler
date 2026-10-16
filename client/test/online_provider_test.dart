import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/application/online_provider.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'api_fixture.dart';

void main() {
  test('Provider 销毁时取消尚未完成的登录，不恢复旧会话', () async {
    final pending = Completer<ResponseBody>();
    late ApiSession session;
    final container = ProviderContainer(
      overrides: [
        apiOriginProvider.overrideWithValue('https://example.invalid'),
        apiFactoryProvider.overrideWithValue((origin, expired) {
          session = ApiSession(
            origin,
            onExpired: expired,
            dio: Dio()..httpClientAdapter = TestAdapter((_) => pending.future),
          );
          return session;
        }),
      ],
    );
    final login = container
        .read(onlineProvider.notifier)
        .login('fictional@example.invalid', 'fictional-password');
    final assertion = expectLater(login, throwsA(isA<ApiFailure>()));
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    pending.complete(reply(tokens()));
    await assertion;
    expect(session.authenticated, false);
  });
  registerReplacementTest();
}

void registerReplacementTest() {
  test('第二次登录不被第一次的晚到响应覆盖', () async {
    final pending = Completer<ResponseBody>();
    var count = 0;
    final container = ProviderContainer(
      overrides: [
        apiOriginProvider.overrideWithValue('https://example.invalid'),
        apiFactoryProvider.overrideWithValue((origin, expired) {
          count++;
          final first = count == 1;
          return ApiSession(
            origin,
            onExpired: expired,
            dio: Dio()
              ..httpClientAdapter = TestAdapter(
                (_) => first ? pending.future : reply(tokens('two')),
              ),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(onlineProvider.notifier);
    final first = controller.login(
      'first@example.invalid',
      'fictional-password',
    );
    final assertion = expectLater(first, throwsA(isA<ApiFailure>()));
    await controller.login('second@example.invalid', 'fictional-password');
    final current = container.read(onlineProvider);
    pending.complete(reply(tokens()));
    await assertion;
    expect(current, isNotNull);
    expect(identical(container.read(onlineProvider), current), true);
  });
}
