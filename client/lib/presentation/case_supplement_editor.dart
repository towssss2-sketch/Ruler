import 'package:flutter/material.dart';
import '../domain/case_supplement.dart';
import '../domain/experience.dart';
import 'online_widgets.dart';

/// 从授权详情编辑六项资料；失败保留草稿，保存期间禁止返回和重复提交。
class CaseSupplementEditor extends StatefulWidget {
  const CaseSupplementEditor({
    required this.initial,
    required this.save,
    this.offline = false,
    super.key,
  });
  final CaseSupplement initial;
  final Future<void> Function(CaseSupplement) save;
  final bool offline;
  @override
  State<CaseSupplementEditor> createState() => _CaseSupplementEditorState();
}

class _CaseSupplementEditorState extends State<CaseSupplementEditor> {
  late final _judge = TextEditingController(text: widget.initial.judge);
  late final _clerk = TextEditingController(text: widget.initial.clerk);
  late final _phone = TextEditingController(text: widget.initial.clerkPhone);
  late final _fee = TextEditingController(text: widget.initial.fee);
  late final _notes = TextEditingController(text: widget.initial.notes);
  late String _status = widget.initial.feeStatus;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_judge, _clerk, _phone, _fee, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final value = CaseSupplement(
      judge: _judge.text,
      clerk: _clerk.text,
      clerkPhone: _phone.text,
      fee: _fee.text,
      notes: _notes.text,
      feeStatus: _status,
    );
    if (value.error != null) {
      setState(() => _error = value.error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      await widget.save(value.normalized);
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
    child: Scaffold(
      appBar: AppBar(title: const Text('编辑其他案件信息')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _fields(),
              ),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('取消编辑'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(
                      _busy
                          ? '保存中…'
                          : widget.offline
                          ? '保存体验资料'
                          : '保存案件资料',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _fields() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.offline ? '仅本次虚构体验，关闭应用后清除。' : '仅填写虚构资料；保存后同步到测试服务。'),
      const Text('可选资料留空并保存会清除原值。费用状态只作记录，不执行收款或付款。'),
      _field(_judge, '审判员', 128),
      _field(_clerk, '书记员', 128),
      _field(_phone, '书记员电话', 64, keyboard: TextInputType.phone),
      _field(
        _fee,
        '费用金额（元）',
        15,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
      ),
      DropdownButtonFormField<String>(
        initialValue: _status,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '费用状态'),
        items: feeStatuses.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: _busy
            ? null
            : (value) {
                if (value != null) setState(() => _status = value);
              },
      ),
      _field(_notes, '备注', 10000, multiline: true),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label,
    int limit, {
    bool multiline = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey(label),
      controller: controller,
      enabled: !_busy,
      maxLength: limit,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 6 : 1,
      keyboardType: multiline ? TextInputType.multiline : keyboard,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
