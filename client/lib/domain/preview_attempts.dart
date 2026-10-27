import 'online.dart';

/// 仅提取状态和时间，不包含正文、案件候选或对象地址。
class PreviewAttempt {
  const PreviewAttempt({
    required this.id,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.reason,
    this.retryable = false,
  });
  final String id, status;
  final String? reason;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final bool retryable;
}

abstract interface class PreviewAttempts {
  Future<OnlinePage<PreviewAttempt>> attempts(String id, {int page = 1});
}

const previewAttemptStatuses = {
  'RUNNING': '处理中',
  'SUCCEEDED': '提取成功',
  'MANUAL_REQUIRED': '需人工处理',
  'INTERRUPTED': '处理已中断',
};
