import '../domain/case_detail.dart';
import '../domain/case_conflict.dart';
import 'case_conflict_wire.dart';
import 'case_detail_wire.dart';
import '../domain/case_fields.dart';
import '../domain/case_filters.dart';
import '../domain/online.dart';
import 'api_session.dart';
import '../domain/task_fields.dart';
import 'task_wire.dart';
import '../domain/today.dart';
import 'today_wire.dart';

/// 真实 REST 仓库；每次查询服务端，关闭客户端不清除已保存案件。
class ApiRepository implements OnlineRepository {
  ApiRepository(this.session);
  final ApiSession session;

  /// 今日按服务端北京时间、优先级与全量分页读取，不传用户或案件范围。
  @override
  Future<TodaySnapshot> today({int page = 1}) async => readToday(
    await session.request(
      'GET',
      '/tasks/today',
      query: {'page': page, 'pageSize': 20},
    ),
    page,
  );

  @override
  Future<OnlinePage<OnlineCase>> cases({
    String keyword = '',
    int page = 1,
    CaseFilters filters = const CaseFilters(),
  }) async {
    if (filters.error != null) throw ApiFailure(filters.error!);
    final result = await session.request(
      'GET',
      '/cases',
      query: {
        'page': page,
        'pageSize': 20,
        ...filters.toQuery(),
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
    return _page(result, _case);
  }

  @override
  Future<OnlineCase> createCase(
    String number,
    String cause,
    String court,
    String party,
  ) => createCaseWithParties(number, cause, court, [
    CaseParty(name: party, role: 'PLAINTIFF'),
  ]);

  /// 一个请求原子创建案件及完整名单，不用后续 PATCH 补齐新建数据。
  @override
  Future<OnlineCase> createCaseWithParties(
    String number,
    String cause,
    String court,
    List<CaseParty> parties,
  ) async {
    final error = validateNewParties(parties);
    if (error != null) throw ApiFailure(error);
    return _case(
      jsonObject(
        await session.request(
          'POST',
          '/cases',
          data: {
            'caseNo': number,
            'cause': cause,
            'court': court,
            'parties': parties.map((party) => party.toJson()).toList(),
          },
        ),
      ),
    );
  }

  /// 服务端检查已保存名单；不接受客户端设置用户范围或匹配阈值。
  @override
  Future<OnlinePage<CaseConflict>> conflicts(String id, {int page = 1}) async =>
      readConflictPage(
        await session.request(
          'POST',
          '/cases/${Uri.encodeComponent(id)}/conflict-check',
          query: {'page': page, 'pageSize': 20},
        ),
        expectedPage: page,
      );

  /// 仅提交基础字段；保留后端未提交字段，权限与冲突仍由服务端裁决。
  @override
  Future<OnlineCase> updateCase(String id, CaseFields fields) async => _case(
    jsonObject(
      await session.request(
        'PATCH',
        '/cases/${Uri.encodeComponent(id)}',
        data: fields.toJson(),
      ),
    ),
  );

  /// 实时读取授权详情，不使用摘要或另一案件缓存代替当事人名单。
  @override
  Future<CaseDetail> caseDetail(String id) async => readCaseDetail(
    await session.request('GET', '/cases/${Uri.encodeComponent(id)}'),
  );

  /// 仅更新当事人名单；完成写入后由页面独立刷新，读失败不重复写入。
  @override
  Future<void> saveParties(String id, List<CaseParty> parties) async {
    final error = validateParties(parties);
    if (error != null) throw ApiFailure(error);
    await session.request(
      'PATCH',
      '/cases/${Uri.encodeComponent(id)}',
      data: {'parties': parties.map((party) => party.toJson()).toList()},
    );
  }

  @override
  Future<void> removeCase(String id) async {
    await session.request('DELETE', '/cases/${Uri.encodeComponent(id)}');
  }

  /// 仅写六项其他资料；成功后独立重读，读失败不会重复提交。
  @override
  Future<void> saveSupplement(String id, CaseSupplement value) async {
    if (value.error != null) throw ApiFailure(value.error!);
    await session.request(
      'PATCH',
      '/cases/${Uri.encodeComponent(id)}',
      data: value.normalized.toJson(),
    );
  }

  @override
  Future<OnlinePage<OnlineTask>> tasks(String caseId, {int page = 1}) async {
    final result = await session.request(
      'GET',
      '/cases/${Uri.encodeComponent(caseId)}/tasks',
      query: {'source': 'MANUAL', 'page': page, 'pageSize': 20},
    );
    return _page(result, readManualTask);
  }

  @override
  Future<void> addTask(
    String caseId,
    String title,
    String? dueDate, {
    String? description,
  }) async {
    final fields = TaskFields(
      title: title,
      dueDate: dueDate,
      description: description,
    );
    if (fields.error != null) throw ApiFailure(fields.error!);
    await session.request(
      'POST',
      '/cases/${Uri.encodeComponent(caseId)}/tasks',
      data: fields.normalized.toJson(),
    );
  }

  /// 保存手动任务三项资料；不携带状态/来源/确认字段，授权由服务端实时裁决。
  @override
  Future<void> updateTask(String id, TaskFields fields) async {
    if (fields.error != null) throw ApiFailure(fields.error!);
    await session.request(
      'PATCH',
      '/tasks/${Uri.encodeComponent(id)}',
      data: fields.normalized.toJson(),
    );
  }

  @override
  Future<void> setTaskDone(String id, bool done) async {
    await session.request(
      'PATCH',
      '/tasks/${Uri.encodeComponent(id)}',
      data: {'status': done ? 'DONE' : 'TODO'},
    );
  }

  @override
  Future<void> removeTask(String id) async {
    await session.request('DELETE', '/tasks/${Uri.encodeComponent(id)}');
  }
}

OnlineCase _case(Map<String, Object?> value) {
  final stage = jsonText(value, 'stage');
  final status = jsonText(value, 'status');
  if (!caseStages.containsKey(stage) || !caseStatuses.containsKey(status)) {
    throw const ApiFailure('服务响应格式异常。');
  }
  return OnlineCase(
    jsonText(value, 'id'),
    jsonText(value, 'caseNo'),
    jsonText(value, 'cause'),
    jsonText(value, 'court'),
    stage: stage,
    status: status,
  );
}

OnlinePage<T> _page<T>(Object? result, T Function(Map<String, Object?>) parse) {
  final value = jsonObject(result);
  final items = value['items'];
  final total = value['total'];
  final page = value['page'];
  if (items is! List ||
      total is! int ||
      total < 0 ||
      page is! int ||
      page < 1) {
    throw const ApiFailure('服务响应格式异常。');
  }
  return OnlinePage(
    items.map((item) => parse(jsonObject(item))).toList(),
    total,
    page,
  );
}
