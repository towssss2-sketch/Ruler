import 'package:ruler_client/domain/case_detail.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'connected_e2e.dart' show check, forbidden;

String? _retainedId;

/// 实际名单更新：原记录保留 id，新记录分配 id，可选字段清空，移除后不再出现在详情。
Future<void> partyScenario(ApiRepository repository, String id) async {
  final before = await repository.caseDetail(id);
  _retainedId = before.parties.single.id;
  await repository.saveParties(id, [
    CaseParty(
      id: _retainedId,
      name: '虚构甲更新',
      role: 'DEFENDANT',
      phone: '虚构电话',
      idCard: '虚构证件',
      address: '虚构地址',
    ),
    const CaseParty(name: '虚构乙待移除', role: 'THIRD_PARTY'),
  ]);
  final created = await repository.caseDetail(id);
  check(created.parties.length == 2);
  final retained = created.parties.singleWhere(
    (party) => party.id == _retainedId,
  );
  check(
    retained.phone == '虚构电话' &&
        retained.idCard == '虚构证件' &&
        retained.address == '虚构地址',
  );
  final removedId = created.parties
      .singleWhere((party) => party.name == '虚构乙待移除')
      .id;
  check(removedId != null && removedId != _retainedId);
  await repository.saveParties(id, [
    CaseParty(
      id: _retainedId,
      name: '虚构甲更新',
      role: 'DEFENDANT',
      idCard: '虚构证件',
      address: '虚构新地址',
    ),
    const CaseParty(name: '虚构丙新增', role: 'PLAINTIFF'),
  ]);
  final after = await repository.caseDetail(id);
  check(after.parties.every((party) => party.id != removedId));
  check(
    after.notes == before.notes &&
        after.fee == before.fee &&
        after.judge == before.judge,
  );
  check(
    after.fields.caseNo == before.fields.caseNo &&
        after.fields.status == before.fields.status,
  );
  check(after.documentCount == 1 && after.pendingTaskCount == 1);
  await verifyPartyPersistence(repository, id);
  await foreignParty(repository, id);
}

/// 重登后的新仓库读取真实保存的名单及敏感可选字段，不复用前一界面。
Future<void> verifyPartyPersistence(ApiRepository repository, String id) async {
  final detail = await repository.caseDetail(id);
  check(detail.parties.length == 2);
  final kept = detail.parties.singleWhere((party) => party.id == _retainedId);
  check(kept.name == '虚构甲更新' && kept.role == 'DEFENDANT');
  check(kept.phone == null && kept.idCard == '虚构证件' && kept.address == '虚构新地址');
  check(
    detail.parties.singleWhere((party) => party.name == '虚构丙新增').role ==
        'PLAINTIFF',
  );
  check((await repository.cases(keyword: '虚构丙新增')).items.single.id == id);
}

/// 同一账号也不能把另一案件的当事人 id 搬过来，失败不留下半份名单。
Future<void> foreignParty(ApiRepository repository, String id) async {
  final other = await repository.createCase(
    '(2026)虚构民初26号',
    '虚构外案',
    '虚构法院',
    '虚构外案人员',
  );
  final foreign = (await repository.caseDetail(other.id)).parties.single;
  var denied = false;
  try {
    await repository.saveParties(id, [foreign]);
  } on ApiFailure catch (error) {
    denied = error.message.startsWith('填写内容不符合要求');
  }
  check(denied);
  await verifyPartyPersistence(repository, id);
  check(
    (await repository.caseDetail(other.id)).parties.single.id == foreign.id,
  );
  await repository.removeCase(other.id);
}

/// 另一账号既不能读取详情，也不能用合法形状的名单覆盖他人案件。
Future<void> partyIsolation(ApiRepository repository, String id) async {
  await forbidden(() async {
    await repository.caseDetail(id);
  });
  await forbidden(
    () => repository.saveParties(id, [
      const CaseParty(name: '虚构越权', role: 'PLAINTIFF'),
    ]),
  );
}
