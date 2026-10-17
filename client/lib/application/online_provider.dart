import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/online.dart';
import '../infrastructure/api_repository.dart';
import '../infrastructure/api_session.dart';

/// 地址由测试包构建配置提供；默认空值不会暗连任何外部服务。
final apiOriginProvider = Provider<String>(
  (ref) => const String.fromEnvironment('RULER_API_URL'),
);
final apiFactoryProvider =
    Provider<ApiSession Function(String, void Function())>(
      (ref) =>
          (origin, expired) => ApiSession(origin, onExpired: expired),
    );
final onlineProvider = NotifierProvider<OnlineController, OnlineRepository?>(
  OnlineController.new,
);

/// 管理单一内存会话；换账号或失效时销毁整个连接版页面树。
class OnlineController extends Notifier<OnlineRepository?> {
  ApiSession? _session;
  int _generation = 0;

  @override
  OnlineRepository? build() {
    ref.onDispose(() {
      _generation++;
      _session?.close();
    });
    return null;
  }

  /// 仅成功登录后发布仓库；过期的登录结果不能覆盖新会话。
  Future<void> login(String email, String password) async {
    final origin = ref.read(apiOriginProvider);
    if (origin.isEmpty) throw const ApiFailure('测试服务尚未开放，请等待连接版测试包。');
    final generation = ++_generation;
    _session?.close();
    state = null;
    final session = ref.read(apiFactoryProvider)(origin, () {
      if (generation == _generation) {
        _generation++;
        _session = null;
        state = null;
      }
    });
    _session = session;
    try {
      await session.login(email, password);
      if (generation != _generation) {
        session.close();
        throw const ApiFailure('登录已取消。');
      }
      state = ApiRepository(session);
    } catch (_) {
      session.close();
      rethrow;
    }
  }

  /// 登出后始终移除本地案件与任务页面，保留服务端失败提示。
  Future<void> logout() async {
    final session = _session;
    final generation = ++_generation;
    try {
      await session?.logout();
    } finally {
      if (generation == _generation) {
        _session = null;
        state = null;
      }
    }
  }
}
