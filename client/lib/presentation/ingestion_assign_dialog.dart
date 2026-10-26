import 'package:flutter/material.dart';
import '../domain/ingestion.dart';
import '../domain/ingestion_assignment.dart';
import '../domain/documents.dart';
import '../domain/online.dart';
import 'ingestion_case_picker.dart';
import 'online_widgets.dart';

class IngestionAssignDialog extends StatefulWidget {
  const IngestionAssignDialog({
    required this.item,
    required this.repository,
    this.offline = false,
    this.initialCategory,
    super.key,
  });
  final IngestionItem item;
  final IngestionAssignment repository;
  final bool offline;
  final String? initialCategory;
  @override
  State<IngestionAssignDialog> createState() => _IngestionAssignDialogState();
}

class _IngestionAssignDialogState extends State<IngestionAssignDialog> {
  OnlineCase? _selected;
  late String? _category = widget.initialCategory;
  String? _error;
  bool _busy = false;
  Future<void> _choose() async {
    final result = await showDialog<OnlineCase>(
      context: context,
      useRootNavigator: false,
      builder: (_) => IngestionCasePicker(repository: widget.repository),
    );
    if (mounted && result != null) {
      setState(() {
        _selected = result;
        _error = null;
      });
    }
  }

  Future<void> _assign() async {
    if (_busy) return;
    if (_selected == null || _category == null) {
      setState(() => _error = '请选择案件和文件分类。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.assign(
        widget.item.id,
        _selected!.id,
        _category!,
        revision: widget.item.assignmentRevision,
      );
      if (mounted) {
        Navigator.pop(
          context,
          '已归入 ${_selected!.caseNo} · ${documentCategories[_category]}。可在该案件的文件列表查看。',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = onlineError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('分类归档'),
      content: _content(),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _assign,
          child: Text(_error == null ? '确认归档' : '重试归档'),
        ),
      ],
    ),
  );
  Widget _content() => SizedBox(
    width: 520,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.item.file!.name),
          if (widget.initialCategory != null)
            const Text('已带入建议分类，可修改；仍需选择案件并确认归档。'),
          const SizedBox(height: 12),
          Text(
            widget.offline
                ? '仅归档虚构示例，无真实原件；关闭应用清除。'
                : '保留待定区原件，并在案件中保存一份副本，新增占用 ${widget.item.file!.size} 字节。请核对案件和分类后确认。',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _choose,
            child: const Text('选择案件'),
          ),
          if (_selected != null)
            Text(
              '${_selected!.caseNo}\n${_selected!.court}\n${_selected!.cause}',
            ),
          const SizedBox(height: 12),
          _categoryField(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    ),
  );

  Widget _categoryField() => DropdownButtonFormField<String>(
    initialValue: _category,
    isExpanded: true,
    decoration: const InputDecoration(labelText: '文件分类（必选）'),
    items: [
      for (final entry in documentCategories.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: _busy
        ? null
        : (value) => setState(() {
            _category = value;
            _error = null;
          }),
  );
}
