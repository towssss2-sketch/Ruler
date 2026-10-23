import 'package:ruler_client/infrastructure/api_ingestion.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'connected_e2e.dart' show check, forbidden;

/// 真正的接收、去重、重登、权限隔离与忽略；不使用协议夹具或数据库直写。
Future<void> ingestionScenario(
  ApiSession first,
  String origin,
  String ownerEmail,
  String otherEmail,
  String password,
) async {
  final repo = ApiIngestion(first);
  final text = '虚构微信文字\n请核对材料归属。';
  check((await repo.list()).total == 0);
  final receipt = await repo.receive('  ${text.replaceAll('\n', '\r\n')}  ');
  check(!receipt.duplicate && receipt.status == 'PENDING_MATCH');
  check((await repo.receive(text)).id == receipt.id);
  check((await repo.list()).items.single.id == receipt.id);
  check((await repo.detail(receipt.id)).rawContent == text);
  final other = ApiSession(origin);
  final reopenedSession = ApiSession(origin);
  try {
    await other.login(otherEmail, password);
    final isolated = ApiIngestion(other);
    check((await isolated.list(history: true)).total == 0);
    await forbidden(() async {
      await isolated.detail(receipt.id);
    });
    await forbidden(() => isolated.ignore(receipt.id));
    await other.logout();
    await reopenedSession.login(ownerEmail, password);
    final reopened = ApiIngestion(reopenedSession);
    check((await reopened.detail(receipt.id)).rawContent == text);
    await reopened.ignore(receipt.id);
    await reopened.ignore(receipt.id);
    check((await reopened.list()).total == 0);
    check(
      (await reopened.list(history: true)).items.single.status == 'IGNORED',
    );
    final retry = await reopened.receive(text);
    check(retry.duplicate && retry.status == 'IGNORED');
    check((await reopened.detail(receipt.id)).rawContent == text);
    await reopenedSession.logout();
  } finally {
    other.close();
    reopenedSession.close();
  }
}
