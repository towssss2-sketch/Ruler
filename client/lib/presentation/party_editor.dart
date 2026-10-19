import 'package:flutter/material.dart';
import '../domain/case_detail.dart';
import '../domain/experience.dart';
import 'online_widgets.dart';
import 'party_fields.dart';

/// 全列表编辑，提交成功后才退出；取消/移除草稿均不提前修改服务端。
class PartyEditor extends StatefulWidget {
  const PartyEditor({
    required this.parties,
    required this.save,
    this.offline = false,
    super.key,
  });
  final List<CaseParty> parties;
  final Future<void> Function(List<CaseParty>) save;
  final bool offline;
  @override
  State<PartyEditor> createState() => _PartyEditorState();
}

class _PartyEditorState extends State<PartyEditor> {
  late final _rows =
      (widget.parties.isEmpty
              ? [const CaseParty(name: '', role: 'PLAINTIFF')]
              : widget.parties)
          .map(PartyFields.new)
          .toList();
  final _retired = <PartyFields>[];
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final row in [..._rows, ..._retired]) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _remove(PartyFields row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('从本次编辑中移除此人？'),
        content: const Text('保存后才会从案件中移除。取消整个编辑可保留原记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认移除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && !_busy && _rows.length > 1) {
      setState(() {
        _rows.remove(row);
        _retired.add(row);
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final values = _rows.map((row) => row.value).toList();
    final error = validateParties(values);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(values);
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
      appBar: AppBar(
        title: const Text('编辑当事人'),
        leading: BackButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.offline
                    ? '仅虚构体验，关闭应用后清除。至少保留一人。'
                    : '仅填写虚构资料。至少保留一人；保存整份名单，取消不写入。',
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _rows.length,
                itemBuilder: (context, index) => PartyFieldsCard(
                  key: _rows[index].key,
                  fields: _rows[index],
                  index: index,
                  busy: _busy,
                  remove: _rows.length > 1 ? () => _remove(_rows[index]) : null,
                ),
              ),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            _actions(),
          ],
        ),
      ),
    ),
  );

  Widget _actions() => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    children: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消编辑'),
      ),
      OutlinedButton(
        onPressed: _busy || _rows.length >= 100
            ? null
            : () => setState(() {
                _rows.add(
                  PartyFields(const CaseParty(name: '', role: 'DEFENDANT')),
                );
              }),
        child: Text('添加当事人（${_rows.length}/100）'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(
          _busy
              ? '保存中…'
              : widget.offline
              ? '保存体验当事人'
              : '保存当事人',
        ),
      ),
    ],
  );
}
