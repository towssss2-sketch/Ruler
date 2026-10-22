/// 手动任务可编辑资料；工作日期是日历日期，不包含时区或法定期间判断。
class TaskFields {
  const TaskFields({required this.title, this.description, this.dueDate});
  final String title;
  final String? description, dueDate;

  String? get error {
    if (title.trim().isEmpty || title.trim().runes.length > 255) {
      return '请填写 1–255 字的任务标题';
    }
    if ((description?.trim().runes.length ?? 0) > 10000) {
      return '任务描述不能超过 10000 字';
    }
    final date = _optional(dueDate);
    return date != null && !validWorkDate(date) ? '请输入有效工作日期' : null;
  }

  TaskFields get normalized => TaskFields(
    title: title.trim(),
    description: _optional(description),
    dueDate: _optional(dueDate),
  );

  /// 编辑仅提交三字段，空描述/日期明确清空，不修改完成状态或任务来源。
  Map<String, Object?> toJson() => {
    'title': title,
    'description': description,
    'dueDate': dueDate,
  };
}

bool validWorkDate(String value) {
  if (!RegExp(r'^[1-9]\d{3}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null && date.toIso8601String().substring(0, 10) == value;
}

String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
