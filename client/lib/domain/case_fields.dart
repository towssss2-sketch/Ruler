/// 与后端枚举一致；仅编辑基础信息，不携带当事人、费用或文件字段。
const caseStages = {
  'FIRST_INSTANCE': '一审',
  'SECOND_INSTANCE': '二审',
  'ENFORCEMENT': '执行',
  'RETRIAL': '再审',
};
const caseStatuses = {'ACTIVE': '进行中', 'CLOSED': '已结案'};

class CaseFields {
  const CaseFields({
    required this.caseNo,
    required this.cause,
    required this.court,
    this.stage = 'FIRST_INSTANCE',
    this.status = 'ACTIVE',
  });
  final String caseNo;
  final String cause;
  final String court;
  final String stage;
  final String status;

  Map<String, Object?> toJson() => {
    'caseNo': caseNo,
    'cause': cause,
    'court': court,
    'stage': stage,
    'status': status,
  };
}

String normalizeCaseNumber(String value) => value
    .replaceAll('（', '(')
    .replaceAll('）', ')')
    .replaceAll(RegExp(r'\s'), '');

String? validateCaseNumber(String? value) {
  final number = normalizeCaseNumber(value ?? '');
  return RegExp(
        r'^\([12]\d{3}\)[\p{Script=Han}\d]{1,60}号$',
        unicode: true,
      ).hasMatch(number)
      ? null
      : '请输入完整案号，例如 (2026)虚构民初1号';
}
