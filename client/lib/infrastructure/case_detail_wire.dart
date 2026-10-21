import '../domain/case_detail.dart';
import '../domain/case_fields.dart';
import '../domain/online.dart';
import 'api_session.dart';

/// 严格解析授权详情；未知枚举、重复身份或损坏字段均拒绝，不展示原响应。
CaseDetail readCaseDetail(Object? raw) {
  final value = jsonObject(raw);
  final stage = jsonText(value, 'stage');
  final status = jsonText(value, 'status');
  final supplement = _supplement(value);
  final parties = value['parties'];
  if (!caseStages.containsKey(stage) ||
      !caseStatuses.containsKey(status) ||
      parties is! List ||
      parties.length > 100) {
    throw const ApiFailure('服务响应格式异常。');
  }
  final parsed = parties.map((item) {
    final party = jsonObject(item);
    return CaseParty(
      id: jsonText(party, 'id'),
      name: jsonText(party, 'name'),
      role: jsonText(party, 'role'),
      phone: optionalText(party, 'phone'),
      idCard: optionalText(party, 'idCard'),
      address: optionalText(party, 'address'),
    );
  }).toList();
  if (parsed.isNotEmpty && validateParties(parsed) != null) {
    throw const ApiFailure('服务响应格式异常。');
  }
  return CaseDetail(
    id: jsonText(value, 'id'),
    fields: CaseFields(
      caseNo: jsonText(value, 'caseNo'),
      cause: jsonText(value, 'cause'),
      court: jsonText(value, 'court'),
      stage: stage,
      status: status,
    ),
    parties: parsed,
    documentCount: count(value, 'documentCount'),
    pendingTaskCount: count(value, 'pendingTaskCount'),
    judge: supplement.judge,
    clerk: supplement.clerk,
    clerkPhone: supplement.clerkPhone,
    notes: supplement.notes,
    fee: supplement.fee,
    feeStatus: supplement.feeStatus,
  );
}

CaseSupplement _supplement(Map<String, Object?> value) {
  final result = CaseSupplement(
    judge: optionalText(value, 'judge'),
    clerk: optionalText(value, 'clerk'),
    clerkPhone: optionalText(value, 'clerkPhone'),
    notes: optionalText(value, 'notes'),
    fee: optionalText(value, 'fee'),
    feeStatus: jsonText(value, 'feeStatus'),
  );
  if (result.error != null) throw const ApiFailure('服务响应格式异常。');
  return result;
}

String? optionalText(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result != null && result is! String) throw const ApiFailure('服务响应格式异常。');
  return result as String?;
}

int count(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! int || result < 0) throw const ApiFailure('服务响应格式异常。');
  return result;
}
