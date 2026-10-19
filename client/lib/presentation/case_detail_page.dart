import 'package:flutter/material.dart';
import '../domain/case_detail.dart';
import '../domain/case_fields.dart';
import 'online_widgets.dart';
import 'party_editor.dart';

/// 在线每次加载真实授权详情；离线由专用回调读取当前虚构快照。
class CaseDetailPage extends StatefulWidget {
  const CaseDetailPage({
    required this.load,
    required this.saveParties,
    this.offline = false,
    super.key,
  });
  final Future<CaseDetail> Function() load;
  final Future<void> Function(List<CaseParty>) saveParties;
  final bool offline;
  @override
  State<CaseDetailPage> createState() => _CaseDetailPageState();
}

class _CaseDetailPageState extends State<CaseDetailPage> {
  late Future<CaseDetail> _result = _read();
  void _reload() => setState(() {
    _result = _read();
  });

  Future<CaseDetail> _read() {
    final pending = Future<CaseDetail>.sync(widget.load);
    // 提前接住下一帧订阅前的错误；原 future 仍交给 FutureBuilder 展示错误与重试。
    pending.ignore();
    return pending;
  }

  Future<void> _edit(CaseDetail detail) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PartyEditor(
          parties: detail.parties,
          save: widget.saveParties,
          offline: widget.offline,
        ),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('案件详情与当事人'),
      actions: [
        IconButton(
          tooltip: '刷新案件详情',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: OnlineResult(future: _result, retry: _reload, render: _detail),
    ),
  );

  Widget _detail(CaseDetail detail) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(widget.offline ? '离线虚构体验 · 关闭应用后清除' : '测试服务 · 仅限虚构资料'),
      const SizedBox(height: 12),
      Text(detail.fields.caseNo, style: Theme.of(context).textTheme.titleLarge),
      Text(
        '${detail.fields.cause}\n${detail.fields.court}\n${caseStages[detail.fields.stage]} · ${caseStatuses[detail.fields.status]}',
      ),
      Text(
        widget.offline
            ? '${detail.documentCount} 个示例版本 · ${detail.pendingTaskCount} 项待办'
            : '${detail.documentCount} 份当前文件 · ${detail.pendingTaskCount} 项待办',
      ),
      if (!widget.offline) ...[
        const Divider(),
        Text(
          '审判员：${detail.judge ?? '未填写'}\n书记员：${detail.clerk ?? '未填写'}\n书记员电话：${detail.clerkPhone ?? '未填写'}',
        ),
        Text('费用：${detail.fee ?? '未填写'} · ${feeStatuses[detail.feeStatus]}'),
        Text('备注：${detail.notes ?? '未填写'}'),
      ],
      const Divider(),
      Text(
        '当事人（${detail.parties.length}）',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      OnlineAction(label: '编辑当事人', run: () => _edit(detail)),
      if (detail.parties.isEmpty) const Text('暂无当事人，可点击编辑添加虚构记录'),
      for (final party in detail.parties)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${partyRoles[party.role]} · ${party.name}'),
                Text(
                  '电话：${party.phone ?? '未填写'}\n证件号：${party.idCard ?? '未填写'}\n地址：${party.address ?? '未填写'}',
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
