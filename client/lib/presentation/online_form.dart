import 'package:flutter/material.dart';
import '../domain/online.dart';
import 'online_widgets.dart';

/// 案件或任务的真实保存表单；服务失败保留输入，不冒充保存成功。
class OnlineForm extends StatefulWidget {
  const OnlineForm({required this.repository, this.caseId, super.key});
  final OnlineRepository repository;
  final String? caseId;
  @override
  State<OnlineForm> createState() => _OnlineFormState();
}

class _OnlineFormState extends State<OnlineForm> {
  final _form = GlobalKey<FormState>();
  late final _fields = widget.caseId == null
      ? ['案号', '案由', '法院', '原告姓名（虚构）']
      : ['任务标题', '工作日期（可空，YYYY-MM-DD）'];
  late final _values = List.generate(
    _fields.length,
    (_) => TextEditingController(),
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final value in _values) {
      value.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = _values.map((value) => value.text.trim()).toList();
      if (widget.caseId == null) {
        await widget.repository.createCase(
          values[0],
          values[1],
          values[2],
          values[3],
        );
      } else {
        await widget.repository.addTask(
          widget.caseId!,
          values[0],
          values[1].isEmpty ? null : values[1],
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = onlineError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(String? raw, int index) {
    final value = raw?.trim() ?? '';
    if (widget.caseId != null && index == 1) {
      if (value.isEmpty) return null;
      final date = DateTime.tryParse(value);
      if (!RegExp(r'^[1-9]\d{3}-\d{2}-\d{2}$').hasMatch(value) ||
          date == null ||
          date.toIso8601String().substring(0, 10) != value) {
        return '请输入有效工作日期';
      }
      return null;
    }
    return value.isEmpty ? '请填写${_fields[index]}' : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.caseId == null ? '新建测试案件' : '新增工作任务'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('仅填写虚构资料；工作日期不代表法定期限。'),
              for (var i = 0; i < _fields.length; i++)
                TextFormField(
                  controller: _values[i],
                  enabled: !_busy,
                  maxLength: widget.caseId == null
                      ? (i == 0 ? 80 : 128)
                      : (i == 0 ? 255 : 10),
                  decoration: InputDecoration(labelText: _fields[i]),
                  validator: (value) => _validate(value, i),
                ),
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
          child: Text(_busy ? '保存中…' : '保存到测试服务'),
        ),
      ],
    ),
  );
}
