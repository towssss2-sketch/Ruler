import 'case_fields.dart';
import 'case_supplement.dart';
export 'case_supplement.dart';

const partyRoles = {'PLAINTIFF': '原告', 'DEFENDANT': '被告', 'THIRD_PARTY': '第三人'};

/// 当事人快照；已有记录带 id，新记录不带；空可选值明确清空。
class CaseParty {
  const CaseParty({
    this.id,
    required this.name,
    required this.role,
    this.phone,
    this.idCard,
    this.address,
  });
  final String? id;
  final String name;
  final String role;
  final String? phone;
  final String? idCard;
  final String? address;

  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'role': role,
    'phone': phone,
    'idCard': idCard,
    'address': address,
  };
  CaseParty identified(String value) => CaseParty(
    id: value,
    name: name,
    role: role,
    phone: phone,
    idCard: idCard,
    address: address,
  );
}

/// 授权详情的内存快照，不持久化个人资料或把原始响应用于日志。
class CaseDetail {
  CaseDetail({
    required this.id,
    required this.fields,
    required List<CaseParty> parties,
    required this.documentCount,
    required this.pendingTaskCount,
    this.judge,
    this.clerk,
    this.clerkPhone,
    this.notes,
    this.fee,
    this.feeStatus = 'UNPAID',
  }) : parties = List.unmodifiable(parties);
  final String id;
  final CaseFields fields;
  final List<CaseParty> parties;
  final int documentCount;
  final int pendingTaskCount;
  final String? judge;
  final String? clerk;
  final String? clerkPhone;
  final String? notes;
  final String? fee;
  final String feeStatus;
  CaseSupplement get supplement => CaseSupplement(
    judge: judge,
    clerk: clerk,
    clerkPhone: clerkPhone,
    notes: notes,
    fee: fee,
    feeStatus: feeStatus,
  );
}

/// 对整个列表验证，包括当前屏幕外的行，避免滚动表单漏校验。
String? validateParties(List<CaseParty> parties) {
  if (parties.isEmpty || parties.length > 100) return '请保留 1–100 位当事人';
  final ids = <String>{};
  for (var i = 0; i < parties.length; i++) {
    final party = parties[i];
    if (!partyRoles.containsKey(party.role) ||
        party.name.trim().isEmpty ||
        party.name.runes.length > 128) {
      return '请核对第 ${i + 1} 位当事人的姓名和角色';
    }
    if ((party.phone?.runes.length ?? 0) > 64 ||
        (party.idCard?.runes.length ?? 0) > 64 ||
        (party.address?.runes.length ?? 0) > 1000) {
      return '第 ${i + 1} 位当事人的可选资料过长';
    }
    if (party.id != null && (party.id!.isEmpty || !ids.add(party.id!))) {
      return '当事人记录异常，请重新加载';
    }
  }
  return null;
}

/// 新建名单不能携带既有案件的身份，防止把编辑记录误当新增。
String? validateNewParties(List<CaseParty> parties) =>
    validateParties(parties) ??
    (parties.any((party) => party.id != null) ? '新建名单不能使用已有当事人记录' : null);
