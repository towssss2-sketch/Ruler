import 'package:flutter/material.dart';
import '../domain/online.dart';
import '../domain/case_detail.dart';
import 'draft_party_button.dart';
import 'online_widgets.dart';

/// 案件的真实保存表单；服务失败保留输入，不冒充保存成功。
class OnlineForm extends StatefulWidget {
  const OnlineForm({required this.repository, super.key});
  final OnlineRepository repository;
  @override
  State<OnlineForm> createState() => _OnlineFormState();
}

class _OnlineFormState extends State<OnlineForm> {
  final _form = GlobalKey<FormState>();
  final _fields = ['案号', '案由', '法院', '原告姓名（虚构）'];
  late final _values = List.generate(
    _fields.length,
    (_) => TextEditingController(),
  );
  List<CaseParty>? _parties;
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
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = _values.map((value) => value.text.trim()).toList();
      await widget.repository.createCaseWithParties(
        values[0],
        values[1],
        values[2],
        _parties ?? [CaseParty(name: values[3], role: 'PLAINTIFF')],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = onlineError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(String? raw, int index) {
    final value = raw?.trim() ?? '';
    return value.isEmpty ? '请填写${_fields[index]}' : null;
  }

  List<CaseParty> _currentParties() =>
      _parties ?? [CaseParty(name: _values[3].text.trim(), role: 'PLAINTIFF')];

  Widget _draftButton() => DraftPartyButton(
    parties: _currentParties(),
    current: _currentParties,
    enabled: !_busy,
    change: (values) => setState(() => _parties = values),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('新建测试案件'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('仅填写虚构资料。'),
              for (var i = 0; i < _fields.length; i++)
                if (i != 3 || _parties == null)
                  TextFormField(
                    controller: _values[i],
                    onChanged: i == 3 ? (_) => setState(() {}) : null,
                    enabled: !_busy,
                    maxLength: i == 0 ? 80 : 128,
                    decoration: InputDecoration(labelText: _fields[i]),
                    validator: (value) => _validate(value, i),
                  ),
              _draftButton(),
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
