import 'package:ruler_client/domain/case_fields.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';

const editedCase = CaseFields(
  caseNo: '(2026)虚构民终24号',
  cause: '虚构买卖纠纷',
  court: '虚构二审法院',
  stage: 'SECOND_INSTANCE',
  status: 'CLOSED',
);

/// 真实 PATCH 前后比较详情，确保基础编辑保留未提交的当事人和备注等字段。
Future<void> editCaseScenario(ApiRepository repository, String id) async {
  await repository.session.request(
    'PATCH',
    '/cases/$id',
    data: {'notes': '虚构保留备注', 'judge': '虚构审判员', 'fee': '123.45'},
  );
  final before = jsonObject(
    await repository.session.request('GET', '/cases/$id'),
  );
  final saved = await repository.updateCase(id, editedCase);
  verify(
    saved.caseNo == editedCase.caseNo &&
        saved.stage == 'SECOND_INSTANCE' &&
        saved.status == 'CLOSED',
  );
  final after = jsonObject(
    await repository.session.request('GET', '/cases/$id'),
  );
  verify(before['documentCount'] == 1 && before['pendingTaskCount'] == 1);
  final beforeParties = before['parties'] as List;
  final afterParties = after['parties'] as List;
  verify(beforeParties.length == 1 && afterParties.length == 1);
  final party = jsonObject(beforeParties.single);
  final kept = jsonObject(afterParties.single);
  for (final key in ['id', 'name', 'role', 'phone', 'idCard', 'address']) {
    verify(party[key] == kept[key]);
  }
  for (final key in [
    'notes',
    'judge',
    'clerk',
    'clerkPhone',
    'fee',
    'feeStatus',
    'documentCount',
    'pendingTaskCount',
  ]) {
    verify(before[key] == after[key]);
  }
  final search = await repository.cases(keyword: '虚构甲');
  verify(
    search.items.single.id == id &&
        search.items.single.cause == editedCase.cause,
  );
  verify((await repository.tasks(id)).items.single.title == '虚构持久化任务');
  await duplicateEdit(repository, id);
}

/// 新会话读取数据库中的新案号、阶段和状态，不依赖前一仓库内存。
Future<void> verifyEditedCase(ApiRepository repository, String id) async {
  final result = (await repository.cases(
    keyword: editedCase.caseNo,
  )).items.single;
  verify(
    result.id == id &&
        result.cause == editedCase.cause &&
        result.court == editedCase.court &&
        result.stage == editedCase.stage &&
        result.status == editedCase.status,
  );
}

void verify(bool condition) {
  if (!condition) throw StateError('案件编辑联调断言失败');
}

/// 真实重复案号冲突不能覆盖原案件，清理仅限本次新建的虚构记录。
Future<void> duplicateEdit(ApiRepository repository, String id) async {
  final other = await repository.createCase(
    '(2026)虚构民初25号',
    '虚构冲突用例',
    '虚构法院',
    '虚构乙',
  );
  var rejected = false;
  try {
    await repository.updateCase(other.id, editedCase);
  } on ApiFailure catch (error) {
    rejected = error.message.contains('记录重复');
  }
  verify(rejected);
  verify(
    (await repository.cases(keyword: other.caseNo)).items.single.id == other.id,
  );
  await verifyEditedCase(repository, id);
  await repository.removeCase(other.id);
}
