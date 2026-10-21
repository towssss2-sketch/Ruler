const feeStatuses = {
  'UNPAID': '未付',
  'PARTIAL': '部分已付',
  'PAID': '已付',
  'WAIVED': '免收',
};

/// 案件其他资料；金额始终为十进制字符串，不通过浮点数转换。
class CaseSupplement {
  const CaseSupplement({
    this.judge,
    this.clerk,
    this.clerkPhone,
    this.notes,
    this.fee,
    this.feeStatus = 'UNPAID',
  });
  final String? judge, clerk, clerkPhone, notes, fee;
  final String feeStatus;

  String? get error {
    for (final entry in [
      (judge, 128, '审判员'),
      (clerk, 128, '书记员'),
      (clerkPhone, 64, '书记员电话'),
      (notes, 10000, '备注'),
    ]) {
      if ((entry.$1?.trim().runes.length ?? 0) > entry.$2) {
        return '${entry.$3}不能超过 ${entry.$2} 字';
      }
    }
    final amount = _optional(fee);
    if (amount != null &&
        !RegExp(r'^(0|[1-9]\d{0,11})(\.\d{1,2})?$').hasMatch(amount)) {
      return '费用请输入非负金额，最多 12 位整数和 2 位小数，不使用逗号或科学计数法';
    }
    return feeStatuses.containsKey(feeStatus) ? null : '请选择有效的费用状态';
  }

  CaseSupplement get normalized {
    final amount = _optional(fee);
    final parts = amount?.split('.');
    return CaseSupplement(
      judge: _optional(judge),
      clerk: _optional(clerk),
      clerkPhone: _optional(clerkPhone),
      notes: _optional(notes),
      fee: parts == null
          ? null
          : '${parts.first}.${(parts.length == 1 ? '' : parts.last).padRight(2, '0')}',
      feeStatus: feeStatus,
    );
  }

  /// 六字段整体编辑；空白转 null 清空，不携带基础字段或名单。
  Map<String, Object?> toJson() => {
    'judge': judge,
    'clerk': clerk,
    'clerkPhone': clerkPhone,
    'notes': notes,
    'fee': fee,
    'feeStatus': feeStatus,
  };
}

String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
