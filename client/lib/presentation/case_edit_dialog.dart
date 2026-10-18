import 'package:flutter/material.dart';
import '../domain/case_fields.dart';
import '../domain/experience.dart';
import 'online_widgets.dart';

/// 编辑基础信息；成功才关闭，失败保留表单，保存期间阻止返回和重复提交。
class CaseEditDialog extends StatefulWidget {
  const CaseEditDialog({
    required this.initial,
    required this.save,
    this.offline = false,
    super.key,
  });
  final CaseFields initial;
  final Future<void> Function(CaseFields) save;
  final bool offline;

  @override
  State<CaseEditDialog> createState() => _CaseEditDialogState();
}

class _CaseEditDialogState extends State<CaseEditDialog> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.initial.caseNo);
  late final _cause = TextEditingController(text: widget.initial.cause);
  late final _court = TextEditingController(text: widget.initial.court);
  late String _stage = widget.initial.stage;
  late String _status = widget.initial.status;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _cause.dispose();
    _court.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(
        CaseFields(
          caseNo: normalizeCaseNumber(_number.text),
          cause: _cause.text.trim(),
          court: _court.text.trim(),
          stage: _stage,
          status: _status,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ExperienceFailure
              ? error.message
              : onlineError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('编辑案件信息'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(key: _form, child: _fields()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? '保存中…'
                : widget.offline
                ? '保存体验修改'
                : '保存到测试服务',
          ),
        ),
      ],
    ),
  );

  Widget _fields() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.offline ? '仅本次虚构体验，关闭应用后清除。' : '仅填写虚构资料；保存后同步到测试服务。'),
      _field(_number, '案号', 80, validator: validateCaseNumber),
      _field(_cause, '案由', 128),
      _field(_court, '法院', 128),
      _choice('审理阶段', _stage, caseStages, (value) => _stage = value),
      const SizedBox(height: 12),
      _choice('案件状态', _status, caseStatuses, (value) => _status = value),
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('标记结案会保留案件、文件和任务；不会自动完成任务。'),
      ),
      if (_error != null) Text(_error!, key: const ValueKey('case-edit-error')),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label,
    int limit, {
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    maxLength: limit,
    decoration: InputDecoration(labelText: label),
    validator:
        validator ??
        (value) => (value?.trim().isEmpty ?? true) ? '请填写$label' : null,
  );

  Widget _choice(
    String label,
    String value,
    Map<String, String> choices,
    void Function(String) change,
  ) => DropdownButtonFormField<String>(
    key: ValueKey(label),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: choices.entries
        .map(
          (entry) =>
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        )
        .toList(),
    onChanged: _busy
        ? null
        : (value) {
            if (value != null) setState(() => change(value));
          },
  );
}
