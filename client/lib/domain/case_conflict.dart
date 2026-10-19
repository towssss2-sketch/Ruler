/// 服务端相似姓名候选，不包含匹配姓名或法律判断。
class CaseConflict {
  const CaseConflict({
    required this.caseId,
    required this.caseNo,
    required this.court,
    required this.deleted,
    required this.similarity,
  });
  final String caseId;
  final String caseNo;
  final String court;
  final bool deleted;
  final double similarity;
}
