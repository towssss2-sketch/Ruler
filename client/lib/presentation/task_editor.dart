import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/task_fields.dart';
import '../domain/experience.dart';
import 'online_widgets.dart';

/// 普通任务资料表单；保存中阻止重复提交/返回，成功后由调用方单独重读。
class TaskEditor extends StatefulWidget {
  const TaskEditor({
    required this.initial,
    required this.save,
    this.creating = false,
    this.offline = false,
    super.key,
  });
  final TaskFields initial;
  final Future<void> Function(TaskFields) save;
  final bool creating, offline;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _description = TextEditingController(
    text: widget.initial.description,
  );
  late final _date = TextEditingController(text: widget.initial.dueDate);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final value in [_title, _description, _date]) {
      value.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final fields = TaskFields(
      title: _title.text,
      description: _description.text,
      dueDate: _date.text,
    );
    if (fields.error != null) {
      setState(() => _error = fields.error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      await widget.save(fields.normalized);
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
      title: Text(widget.creating ? '新增工作任务' : '编辑工作任务'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.offline ? '仅本次虚构体验，关闭应用后清除。' : '仅填写虚构资料；保存后同步到测试服务。'),
              const Text('工作日期不代表法定期限。描述和日期留空保存会清除原值；编辑不改变完成状态。'),
              _field(_title, '任务标题', 255),
              _field(_description, '任务描述（可空）', 10000, multiline: true),
              _field(_date, '工作日期（可空，YYYY-MM-DD）', 10),
              if (_error != null) Text(_error!),
            ],
          ),
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
                : widget.creating
                ? '保存到测试服务'
                : '保存任务修改',
          ),
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    int limit, {
    bool multiline = false,
  }) => TextFormField(
    key: ValueKey(label),
    controller: controller,
    enabled: !_busy,
    maxLength: limit,
    maxLengthEnforcement: MaxLengthEnforcement.none,
    minLines: multiline ? 3 : 1,
    maxLines: multiline ? 5 : 1,
    decoration: InputDecoration(labelText: label),
  );
}
