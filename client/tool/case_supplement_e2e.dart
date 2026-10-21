import 'package:ruler_client/domain/case_detail.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'connected_e2e.dart' show check;

const editedSupplement = CaseSupplement(
  judge: '虚构审判员',
  clerk: '虚构书记员',
  clerkPhone: '虚构电话',
  notes: '虚构保留备注\n虚构第二行',
  fee: '999999999999.99',
  feeStatus: 'PARTIAL',
);

/// 使用已有真实案件，检验 null 清空及重填，不增加账号或放宽限流。
Future<void> supplementScenario(ApiRepository repository, String id) async {
  await repository.saveSupplement(id, const CaseSupplement());
  final cleared = await repository.caseDetail(id);
  check(cleared.judge == null && cleared.clerk == null);
  check(cleared.clerkPhone == null && cleared.notes == null);
  check(cleared.fee == null && cleared.feeStatus == 'UNPAID');
  check(cleared.documentCount == 1 && cleared.pendingTaskCount == 1);
  check(cleared.parties.length == 2);
  await repository.saveSupplement(id, editedSupplement);
}

/// 包括新会话重登读取：金额原样返回，可选敏感资料由授权详情读取。
void verifySupplement(CaseDetail detail) {
  final expected = editedSupplement.toJson();
  final actual = detail.supplement.toJson();
  for (final key in expected.keys) {
    check(actual[key] == expected[key]);
  }
}
