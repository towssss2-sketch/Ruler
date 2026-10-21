import '../domain/case_detail.dart';
import '../domain/case_conflict.dart';
import 'case_conflict_wire.dart';
import 'case_detail_wire.dart';
import '../domain/case_fields.dart';
import '../domain/case_filters.dart';
import '../domain/online.dart';
import 'api_session.dart';

/// 真实 REST 仓库；每次查询服务端，关闭客户端不清除已保存案件。
class ApiRepository implements OnlineRepository {
  ApiRepository(this.session);
  final ApiSession session;

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

  @override
  Future<OnlinePage<OnlineTask>> tasks(String caseId, {int page = 1}) async {
    final result = await session.request(
      'GET',
      '/cases/${Uri.encodeComponent(caseId)}/tasks',
      query: {'source': 'MANUAL', 'page': page, 'pageSize': 20},
    );
    return _page(result, _task);
  }

  @override
  Future<void> addTask(String caseId, String title, String? dueDate) async {
    await session.request(
      'POST',
      '/cases/${Uri.encodeComponent(caseId)}/tasks',
      data: {'title': title, 'dueDate': dueDate},
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

OnlineTask _task(Map<String, Object?> value) {
  final status = value['status'];
  final date = value['dueDate'];
  if (!['TODO', 'DONE'].contains(status) ||
      (date != null && !_validDate(date))) {
    throw const ApiFailure('服务响应格式异常。');
  }
  return OnlineTask(
    jsonText(value, 'id'),
    jsonText(value, 'title'),
    status == 'DONE',
    date == null ? null : (date as String).substring(0, 10),
  );
}

bool _validDate(Object value) {
  if (value is! String ||
      !RegExp(r'^[1-9]\d{3}-\d{2}-\d{2}(T.*)?$').hasMatch(value)) {
    return false;
  }
  final date = DateTime.tryParse(value);
  return date != null &&
      date.toIso8601String().substring(0, 10) == value.substring(0, 10);
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
