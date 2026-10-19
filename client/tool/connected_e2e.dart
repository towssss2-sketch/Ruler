import 'party_e2e.dart';
import 'case_edit_e2e.dart';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'document_e2e.dart';
import 'tls_fixture.dart';

final _scenarios = <String>[];

/// 子进程从内存环境读取临时虚构账号，输出仅含固定场景名。
Future<void> main() async {
  try {
    await withFixtureTrust(runScenarios);
  } catch (_) {
    stderr.write('客户端联调准备失败（已隐藏配置及原始异常）');
    exitCode = 1;
  }
}

/// 在默认 HTTP 或局部可信 HTTPS 环境中执行相同应用网络层。
Future<void> runScenarios(bool verifiedTls) async {
  if (verifiedTls) _scenarios.add('API 和文件入口的未受信任证书均被默认客户端拒绝');
  final origin = Platform.environment['RULER_E2E_URL']!;
  final emails =
      (jsonDecode(Platform.environment['RULER_E2E_ACCOUNTS']!) as List)
          .cast<String>();
  final password = Platform.environment['RULER_E2E_PASSWORD']!;
  final first = ApiSession(origin);
  final second = ApiSession(origin);
  try {
    await first.login(emails[0], password);
    final repository = ApiRepository(first);
    final item = await repository.createCase(
      '(2026)虚构民初23号',
      '虚构合同纠纷',
      '虚构测试法院',
      '虚构甲',
    );
    final page = await repository.cases(keyword: '虚构甲');
    check(page.total == 1 && page.items.single.id == item.id);
    final emptyPage = await repository.cases(page: 2);
    check(
      emptyPage.items.isEmpty && emptyPage.total == 1 && emptyPage.page == 2,
    );
    _scenarios.add('真实登录、新建案件、当事人搜索和分页');
    await tasks(repository, item);
    _scenarios.addAll(
      await documentScenarios(first, item.id, emails[0], emails[1], password),
    );
    await editCaseScenario(repository, item.id);
    _scenarios.add('真实修改案件基础信息和结案，保留当事人、文件统计与待办任务');
    await partyScenario(repository, item.id);
    _scenarios.add('真实当事人新增、修改、移除、可选资料清空和外案身份拒绝');
    await first.logout();
    await persistence(origin, emails[0], password, item);
    await second.login(emails[1], password);
    await isolation(second, item);
    await second.logout();
    await removal(origin, emails[0], password, item);
    writeResult(verifiedTls);
  } catch (_) {
    stderr.write('客户端联调断言失败（已隐藏凭据及原始响应）');
    exitCode = 1;
  } finally {
    first.close();
    second.close();
  }
}

/// 只输出固定场景结果，不包含当事人资料、登录凭据或签名。
void writeResult(bool verifiedTls) {
  stdout.write(
    jsonEncode({
      'passed': _scenarios.length,
      'failed': 0,
      'skipped': 0,
      'scenarios': _scenarios,
      'transport': 'REAL_DART_DIO_NEST_POSTGRES_REDIS_MINIO',
      'tls': verifiedTls ? 'LOCAL_TRUSTED_CERTIFICATE' : 'HTTP_LOOPBACK',
      'device': 'NOT_RUN',
      'publicTestService': 'NOT_AVAILABLE',
    }),
  );
}

/// 真实创建、完成、恢复、删除工作任务。
Future<void> tasks(ApiRepository repository, OnlineCase item) async {
  await repository.addTask(item.id, '虚构材料核对', '2026-10-20');
  final task = (await repository.tasks(item.id)).items.single;
  check(task.dueDate == '2026-10-20' && !task.done);
  await repository.setTaskDone(task.id, true);
  check((await repository.tasks(item.id)).items.single.done);
  await repository.setTaskDone(task.id, false);
  check(!(await repository.tasks(item.id)).items.single.done);
  await repository.removeTask(task.id);
  check((await repository.tasks(item.id)).total == 0);
  await repository.addTask(item.id, '虚构持久化任务', null);
  _scenarios.add('真实任务创建、日期、完成、恢复和删除');
}

/// 新客户端实例重新登录后读到数据库保存的案件与任务。
Future<void> persistence(
  String origin,
  String email,
  String password,
  OnlineCase item,
) async {
  final session = ApiSession(origin);
  try {
    await session.login(email, password);
    final repository = ApiRepository(session);
    check((await repository.cases()).items.single.id == item.id);
    await verifyEditedCase(repository, item.id);
    await verifyPartyPersistence(repository, item.id);
    check((await repository.tasks(item.id)).items.single.title == '虚构持久化任务');
    _scenarios.add('销毁客户端后重新登录，案件和任务仍保留');
    await session.logout();
  } finally {
    session.close();
  }
}

/// 另一个真实账号不能读写他人案件或任务。
Future<void> isolation(ApiSession session, OnlineCase item) async {
  final repository = ApiRepository(session);
  check((await repository.cases()).total == 0);
  await partyIsolation(repository, item.id);
  await forbidden(() async {
    await repository.tasks(item.id);
  });
  await forbidden(() => repository.addTask(item.id, '虚构越权测试', null));
  await forbidden(() async {
    await repository.updateCase(item.id, editedCase);
  });
  await forbidden(() => repository.removeCase(item.id));
  _scenarios.add('第二账号看不到且不能修改他人的案件和任务');
}

/// 删除持久化资源，实际验证登出令牌在服务端立即被拒绝。
Future<void> removal(
  String origin,
  String email,
  String password,
  OnlineCase item,
) async {
  String? authorization;
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.headers['Authorization'] is String) {
            authorization = options.headers['Authorization'] as String;
          }
          handler.next(options);
        },
      ),
    );
  final session = ApiSession(origin, dio: dio);
  try {
    await session.login(email, password);
    final repository = ApiRepository(session);
    await repository.removeCase(item.id);
    check((await repository.cases()).total == 0);
    _scenarios.add('案件删除后服务端列表不再显示');
    await session.logout();
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$origin/auth/me'));
      request.headers.set('Authorization', authorization!);
      final response = await request.close();
      check(response.statusCode == 401);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
    check(!session.authenticated);
    _scenarios.add('退出登录后旧凭据立即被真实服务端拒绝');
  } finally {
    session.close();
    authorization = null;
  }
}

/// 断言仅抛固定文本，不打印业务数据或凭据。
void check(bool condition) {
  if (!condition) throw StateError('客户端联调断言失败');
}

/// 检查固定权限提示，避免将原始 HTTP 信息放入测试输出。
Future<void> forbidden(Future<void> Function() action) async {
  var denied = false;
  try {
    await action();
  } on ApiFailure catch (error) {
    denied = error.message.startsWith('无权访问');
  }
  check(denied);
}
