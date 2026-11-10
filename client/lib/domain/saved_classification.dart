/// 指定提取尝试当时的分类结果，不包含正文或案号，不等同已确认归档。
class SavedClassification {
  const SavedClassification({
    required this.attemptId,
    required this.state,
    this.category,
    this.reason,
    this.ruleVersion,
  });
  final String attemptId, state;
  final String? category, reason, ruleVersion;
}

abstract interface class SavedClassifications {
  Future<SavedClassification> classification(String id, String attemptId);
}
