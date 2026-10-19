import 'case_detail.dart';
import 'case_fields.dart';

/// 仅含可显示的固定提示，禁止传入原始响应、凭据或网络异常。
class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.sessionEnded = false});
  final String message;
  final bool sessionEnded;
  @override
  String toString() => message;
}

/// 服务端案件摘要；不把演示文件或演示任务混入真实数据。
class OnlineCase {
  const OnlineCase(
    this.id,
    this.caseNo,
    this.cause,
    this.court, {
    this.stage = 'FIRST_INSTANCE',
    this.status = 'ACTIVE',
  });
  final String id;
  final String caseNo;
  final String cause;
  final String court;
  final String stage;
  final String status;
  CaseFields get fields => CaseFields(
    caseNo: caseNo,
    cause: cause,
    court: court,
    stage: stage,
    status: status,
  );
}

/// 常规工作任务；日期不等于经律师确认的法定期间。
class OnlineTask {
  const OnlineTask(this.id, this.title, this.done, this.dueDate);
  final String id;
  final String title;
  final bool done;
  final String? dueDate;
}

/// 显式分页，避免只展示第一页却暗示已经读完。
class OnlinePage<T> {
  OnlinePage(List<T> items, this.total, this.page)
    : items = List.unmodifiable(items);
  final List<T> items;
  final int total;
  final int page;
  bool get hasNext => page * 20 < total;
}

/// 连接版用例边界；实现必须通过后端授权，不复用内存演示仓库。
abstract interface class OnlineRepository {
  Future<OnlinePage<OnlineCase>> cases({String keyword = '', int page = 1});
  Future<OnlineCase> createCase(
    String number,
    String cause,
    String court,
    String party,
  );
  Future<OnlineCase> updateCase(String id, CaseFields fields);
  Future<CaseDetail> caseDetail(String id);
  Future<void> saveParties(String id, List<CaseParty> parties);
  Future<void> removeCase(String id);
  Future<OnlinePage<OnlineTask>> tasks(String caseId, {int page = 1});
  Future<void> addTask(String caseId, String title, String? dueDate);
  Future<void> setTaskDone(String id, bool done);
  Future<void> removeTask(String id);
}
