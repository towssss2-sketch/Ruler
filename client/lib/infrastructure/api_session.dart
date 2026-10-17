import 'package:dio/dio.dart';
import '../domain/online.dart';

const _expired = ApiFailure('会话已结束，请重新登录。', sessionEnded: true);

/// 仅允许 HTTPS 服务或本机联调；拒绝 URL 凭据、路径和查询参数。
String validateApiOrigin(String value) {
  final uri = Uri.tryParse(value);
  final local =
      uri != null && ['127.0.0.1', 'localhost', '[::1]'].contains(uri.host);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      (uri.scheme != 'https' && !(local && uri.scheme == 'http'))) {
    throw const ApiFailure('测试服务地址无效，请等待新的测试包。');
  }
  return uri.origin;
}

/// Dio 会话只在内存持有凭据；串行轮换，失败不重放旧刷新令牌。
class ApiSession {
  ApiSession(String origin, {Dio? dio, this.onExpired}) : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: validateApiOrigin(origin),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      followRedirects: false,
      validateStatus: (status) => status != null && status < 600,
    );
  }
  final Dio _dio;
  final void Function()? onExpired;
  final CancelToken _cancel = CancelToken();
  String? _access;
  String? _refresh;
  Future<void>? _refreshing;
  bool _closed = false;
  final _closeListeners = <void Function()>{};
  bool get authenticated => !_closed && _access != null;

  /// 文件直传与会话同生命周期；已关闭时立即取消新订阅者。
  void onClose(void Function() listener) {
    if (_closed) {
      listener();
    } else {
      _closeListeners.add(listener);
    }
  }

  /// 文件页面离开时解除监听，避免保存不再使用的传输对象。
  void removeCloseListener(void Function() listener) =>
      _closeListeners.remove(listener);

  /// 仅登录虚构邮箱；错误固定提示，不保留密码或响应原文。
  Future<void> login(String email, String password) async {
    if (_access != null || !email.endsWith('@example.invalid')) {
      throw const ApiFailure('请使用已提供的虚构测试账号。');
    }
    final response = await _send('POST', '/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    if (response.statusCode == 401) {
      throw const ApiFailure('邮箱或密码不正确。');
    }
    _install(_unwrap(response));
  }

  /// 受保护请求最多因守卫 401 重试一次；超时、5xx 不重试写入。
  Future<Object?> request(
    String method,
    String path, {
    Map<String, Object?>? data,
    Map<String, Object?>? query,
  }) async {
    if (!authenticated) throw _expired;
    final sentAccess = _access;
    var response = await _send(
      method,
      path,
      data,
      query: query,
      access: sentAccess,
    );
    if (response.statusCode == 401) {
      // 较晚到达的旧 401 复用已轮换凭据，不再次消费旧刷新令牌。
      if (sentAccess == _access) await _renew();
      if (!authenticated) throw _expired;
      response = await _send(method, path, data, query: query, access: _access);
      if (response.statusCode == 401) {
        _expire();
        throw _expired;
      }
    }
    return _unwrap(response);
  }

  /// 吊销服务端会话；失败也清除本地，并明确提示远端未确认吊销。
  Future<void> logout() async {
    try {
      await request('POST', '/auth/logout');
    } on ApiFailure catch (error) {
      if (!error.sessionEnded) {
        throw const ApiFailure('已清除本机登录；网络异常，服务端退出尚未确认。');
      }
    } finally {
      close();
    }
  }

  /// 关闭后取消在途请求并清除凭据；晚到响应不能恢复旧会话。
  void close() {
    if (_closed) return;
    _closed = true;
    _access = null;
    _refresh = null;
    _cancel.cancel();
    _dio.close(force: true);
    for (final listener in _closeListeners.toList()) {
      listener();
    }
    _closeListeners.clear();
  }

  Future<Response<Object?>> _send(
    String method,
    String path,
    Map<String, Object?>? data, {
    Map<String, Object?>? query,
    String? access,
  }) async {
    if (_closed) throw _expired;
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('://')) {
      throw const ApiFailure('请求路径无效。');
    }
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        cancelToken: _cancel,
        options: Options(
          method: method,
          headers: {if (access != null) 'Authorization': 'Bearer $access'},
        ),
      );
      if (_closed) throw _expired;
      return response;
    } on DioException {
      if (_closed) throw _expired;
      throw const ApiFailure('连接失败，操作结果未确认；请刷新核对后再操作。');
    }
  }

  Future<void> _renew() async {
    final pending = _refreshing;
    if (pending != null) return pending;
    final next = _rotate();
    _refreshing = next;
    try {
      await next;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _rotate() async {
    final credential = _refresh;
    _refresh = null; // 请求结果未知时也不能再次使用。
    try {
      if (credential == null) throw _expired;
      final result = await _send('POST', '/auth/refresh', {
        'refreshToken': credential,
      });
      _install(_unwrap(result));
    } on ApiFailure {
      _expire();
      throw _expired;
    }
  }

  void _install(Object? data) {
    if (_closed) throw _expired;
    final value = jsonObject(data);
    final access = jsonText(value, 'accessToken');
    final refresh = jsonText(value, 'refreshToken');
    if (value['tokenType'] != 'Bearer') throw const ApiFailure('服务响应格式异常。');
    _access = access;
    _refresh = refresh;
  }

  void _expire() {
    if (_closed) return;
    close();
    onExpired?.call();
  }
}

Object? _unwrap(Response<Object?> response) {
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw ApiFailure(switch (status) {
      400 => '填写内容不符合要求，请检查后重试。',
      403 => '无权访问该记录，请返回列表刷新。',
      409 => '记录重复或当前状态不允许操作，请刷新核对。',
      429 => '操作过于频繁，请稍后重试。',
      _ => '服务暂时不可用，请稍后刷新核对。',
    });
  }
  final envelope = jsonObject(response.data);
  if (envelope['code'] != 0 || !envelope.containsKey('data')) {
    throw const ApiFailure('服务响应格式异常。');
  }
  return envelope['data'];
}

/// 严格解析 JSON 对象；异常不附带服务端原文。
Map<String, Object?> jsonObject(Object? value) {
  if (value is! Map<String, Object?>) throw const ApiFailure('服务响应格式异常。');
  return value;
}

/// 读取非空字段，缺失时明确失败而不伪造默认业务内容。
String jsonText(Map<String, Object?> value, String key) {
  final text = value[key];
  if (text is! String || text.isEmpty) throw const ApiFailure('服务响应格式异常。');
  return text;
}
