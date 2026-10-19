import 'package:ruler_client/domain/case_detail.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'connected_e2e.dart' show check, forbidden;

const _name = '虚构紫杉专用甲';
const _parties = [
  CaseParty(name: _name, role: 'PLAINTIFF', phone: '虚构电话'),
  CaseParty(name: _name, role: 'DEFENDANT', address: '虚构地址'),
];

/// 多人原子建案后实际调用 PostgreSQL 相似匹配，检查历史、去重及跨页。
Future<void> conflictScenario(ApiRepository repository) async {
  final source = await repository.createCaseWithParties(
    '(2026)虚构民初100号',
    '虚构冲突检查',
    '虚构测试法院',
    _parties,
  );
  final detail = await repository.caseDetail(source.id);
  check(detail.parties.length == 2);
  check(detail.parties.map((p) => p.id).toSet().length == 2);
  check(detail.parties.every((p) => p.id != null && p.name == _name));
  check(
    detail.parties.singleWhere((p) => p.role == 'PLAINTIFF').phone == '虚构电话',
  );
  check(
    detail.parties.singleWhere((p) => p.role == 'DEFENDANT').address == '虚构地址',
  );
  check((await repository.conflicts(source.id)).total == 0);
  final targets = await createHistory(repository);
  await repository.removeCase(targets.first);
  // 历史案件中已移除的姓名仍参与检查；当前源案件只使用未移除姓名。
  await repository.saveParties(targets.last, [
    const CaseParty(name: '演示桦木人员', role: 'THIRD_PARTY'),
  ]);
  final first = await repository.conflicts(source.id);
  check(first.total == 2 && first.items.length == 2 && !first.hasNext);
  check(first.items.map((m) => m.caseId).toSet().containsAll(targets));
  check(first.items.every((m) => m.similarity == 1 && m.caseId != source.id));
  check(first.items.where((m) => m.deleted).single.caseId == targets.first);
  final empty = await repository.conflicts(source.id, page: 2);
  check(empty.total == 2 && empty.items.isEmpty && empty.page == 2);
  await repository.saveParties(source.id, [
    const CaseParty(name: '演示柏树人员', role: 'PLAINTIFF'),
  ]);
  check((await repository.conflicts(source.id)).total == 0);
  for (final id in targets.skip(1)) {
    await repository.removeCase(id);
  }
  await repository.removeCase(source.id);
}

Future<List<String>> createHistory(ApiRepository repository) async {
  final ids = <String>[];
  for (var index = 1; index <= 2; index++) {
    final item = await repository.createCaseWithParties(
      '(2026)虚构民初${100 + index}号',
      '虚构历史案由',
      '虚构历史法院',
      _parties,
    );
    ids.add(item.id);
  }
  return ids;
}

/// 相同姓名不能泄漏另一账号的历史案件；外案检查仍强制拒绝。
Future<void> conflictIsolation(
  ApiRepository repository,
  String foreignId,
) async {
  await forbidden(() async {
    await repository.conflicts(foreignId);
  });
  final own = await repository.createCaseWithParties(
    '(2026)虚构民初200号',
    '虚构隔离',
    '虚构法院',
    _parties,
  );
  check((await repository.conflicts(own.id)).total == 0);
  await repository.removeCase(own.id);
}
