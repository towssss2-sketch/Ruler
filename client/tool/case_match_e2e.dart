import 'dart:io';
import 'package:ruler_client/infrastructure/api_ingestion_assignment.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'connected_e2e.dart' show check;

/// 使用真实数据库及同一客户端仓库查找文内案号，不使用协议替身或局部页过滤。
Future<String> verifyCaseNumberMatch(
  ApiSession session,
  String number,
  String targetId,
  String otherEmail,
  String password,
) async {
  final repository = ApiRepository(session);
  final matcher = ApiIngestionAssignment(session, repository);
  final alternate = await repository.createCase(
    number,
    '虚构同号另案',
    '虚构另一个法院',
    '虚构乙',
  );
  final decoy = await repository.createCase(
    '(2026)虚构民初190号',
    number,
    '虚构引用法院',
    '虚构丙',
  );
  var alternateRemoved = false;
  try {
    final matched = await matcher.cases(caseNo: number);
    check(matched.total == 2 && matched.items.length == 2);
    check(
      matched.items.every(
        (item) => item.caseNo == number && item.id != decoy.id,
      ),
    );
    check(
      matched.items.map((item) => item.id).toSet().containsAll([
        targetId,
        alternate.id,
      ]),
    );
    final fullWidth = number.replaceAll('(', '（').replaceAll(')', '）');
    check((await matcher.cases(caseNo: ' $fullWidth ')).total == 2);
    check(
      (await matcher.cases(
            caseNo: number,
            keyword: '虚构同号另案',
          )).items.single.id ==
          alternate.id,
    );
    check((await matcher.cases(caseNo: number, page: 2)).items.isEmpty);
    check((await matcher.cases(caseNo: '(2026)虚构民初999号')).total == 0);
    await verifyOtherUser(otherEmail, password, number);
    await repository.removeCase(alternate.id);
    alternateRemoved = true;
    final remaining = await matcher.cases(caseNo: number);
    check(remaining.total == 1 && remaining.items.single.id == targetId);
    return remaining.items.single.id;
  } finally {
    if (!alternateRemoved) await repository.removeCase(alternate.id);
    await repository.removeCase(decoy.id);
  }
}

Future<void> verifyOtherUser(
  String email,
  String password,
  String number,
) async {
  final other = ApiSession(Platform.environment['RULER_E2E_URL']!);
  try {
    await other.login(email, password);
    final result = await ApiIngestionAssignment(
      other,
      ApiRepository(other),
    ).cases(caseNo: number);
    check(result.total == 0 && result.items.isEmpty);
    await other.logout();
  } finally {
    other.close();
  }
}
