import 'package:flutter/material.dart';
import '../domain/case_detail.dart';
import 'party_editor.dart';

/// 暂存于新建表单的名单；退出整份表单即丢弃，没有提前写入服务。
class DraftPartyButton extends StatelessWidget {
  const DraftPartyButton({
    required this.parties,
    required this.enabled,
    required this.change,
    this.current,
    super.key,
  });
  final List<CaseParty> parties;
  final List<CaseParty> Function()? current;
  final bool enabled;
  final ValueChanged<List<CaseParty>> change;

  Future<void> _edit(BuildContext context) async {
    List<CaseParty>? draft;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PartyEditor(
          parties: current?.call() ?? parties,
          draft: true,
          save: (values) async {
            draft = values;
          },
        ),
      ),
    );
    if (context.mounted && saved == true && draft != null) change(draft!);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final party in parties.take(3))
        Text(
          '${partyRoles[party.role]} · ${party.name.isEmpty ? '待填写' : party.name}',
        ),
      if (parties.length > 3) Text('另有 ${parties.length - 3} 人，请打开名单查看'),
      OutlinedButton(
        onPressed: enabled ? () => _edit(context) : null,
        child: Text('编辑新建名单（${parties.length} 人）'),
      ),
      const Text('名单随案件创建。在线案件保存后可检查利益冲突。'),
    ],
  );
}
