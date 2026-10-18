import 'dart:io';
import 'package:dio/dio.dart';

/// 仅联调工具使用本次临时证书；先证明默认客户端拒绝它，再在局部测试区显式信任。
Future<void> withFixtureTrust(Future<void> Function(bool) action) async {
  final certificate = Platform.environment['RULER_E2E_CA_FILE'];
  if (certificate == null) return action(false);
  for (final key in ['RULER_E2E_URL', 'RULER_E2E_STORAGE']) {
    final value = Platform.environment[key]!;
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host != '127.0.0.1' ||
        uri.origin != value) {
      throw StateError('证书联调仅允许本机 HTTPS');
    }
    final probe = Dio();
    var rejected = false;
    try {
      await probe.get<Object?>(
        '$value/health',
        options: Options(followRedirects: false),
      );
    } on DioException catch (error) {
      rejected = error.error is HandshakeException;
    } finally {
      probe.close(force: true);
    }
    if (!rejected) throw StateError('默认客户端未按预期拒绝测试证书');
  }
  final trust = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(await File(certificate).readAsBytes());
  await HttpOverrides.runWithHttpOverrides(
    () => action(true),
    _FixtureTrust(trust),
  );
}

/// 只改变当前联调区的信任根，保持标准握手和主机校验；不进入客户端发布入口。
class _FixtureTrust extends HttpOverrides {
  _FixtureTrust(this.context);
  final SecurityContext context;

  @override
  HttpClient createHttpClient(SecurityContext? _) =>
      super.createHttpClient(context);
}
