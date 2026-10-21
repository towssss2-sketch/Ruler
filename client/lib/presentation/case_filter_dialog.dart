import 'package:flutter/material.dart';
import '../domain/case_fields.dart';
import '../domain/case_filters.dart';

/// 条件先在弹窗中编辑，应用后才改变列表；取消不发起查询。
class CaseFilterDialog extends StatefulWidget {
  const CaseFilterDialog({required this.value, super.key});
  final CaseFilters value;
  @override
  State<CaseFilterDialog> createState() => _CaseFilterDialogState();
}

class _CaseFilterDialogState extends State<CaseFilterDialog> {
  late final _court = TextEditingController(text: widget.value.court);
  late String _stage = widget.value.stage,
      _status = widget.value.status,
      _sort = widget.value.sort;
  String? _error;
  @override
  void dispose() {
    _court.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
    _court.clear();
    _stage = '';
    _status = '';
    _sort = 'desc';
    _error = null;
  });
  void _apply() {
    final result = CaseFilters(
      court: _court.text.trim(),
      stage: _stage,
      status: _status,
      sort: _sort,
    );
    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('筛选与排序'),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _court,
              maxLength: 128,
              decoration: const InputDecoration(
                labelText: '法院（精确匹配）',
                hintText: '填写法院全称，可留空',
              ),
            ),
            _choice('审理阶段', _stage, {
              '': '全部阶段',
              ...caseStages,
            }, (v) => _stage = v),
            _choice('案件状态', _status, {
              '': '全部状态',
              ...caseStatuses,
            }, (v) => _status = v),
            _choice('更新时间排序', _sort, caseSorts, (v) => _sort = v),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(onPressed: _reset, child: const Text('重置条件')),
      FilledButton(onPressed: _apply, child: const Text('应用筛选')),
    ],
  );
  Widget _choice(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: choices.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => change(v));
      },
    ),
  );
}
