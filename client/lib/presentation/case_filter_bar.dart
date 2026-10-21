import 'package:flutter/material.dart';
import '../domain/case_filters.dart';
import 'case_filter_dialog.dart';

/// 当前已应用条件始终可见，清除筛选保留独立的关键词搜索。
class CaseFilterBar extends StatelessWidget {
  const CaseFilterBar({required this.value, required this.change, super.key});
  final CaseFilters value;
  final ValueChanged<CaseFilters> change;
  Future<void> _edit(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final selected = await showDialog<CaseFilters>(
      context: context,
      useRootNavigator: false,
      builder: (_) => CaseFilterDialog(value: value),
    );
    if (context.mounted && selected != null) change(selected);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.filter_list),
              label: const Text('筛选与排序'),
            ),
            if (!value.isDefault)
              TextButton(
                onPressed: () => change(const CaseFilters()),
                child: const Text('清除筛选'),
              ),
          ],
        ),
        Tooltip(
          message: value.summary,
          child: Text(
            value.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
