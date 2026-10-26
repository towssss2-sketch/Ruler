import 'package:flutter/material.dart';
import '../domain/ingestion.dart';
import 'online_widgets.dart';

class IngestionItemCard extends StatelessWidget {
  const IngestionItemCard({
    required this.item,
    required this.detail,
    this.offline = false,
    this.save,
    this.ignore,
    this.assign,
    this.archive,
    this.preview,
    super.key,
  });
  final IngestionItem item;
  final bool offline;
  final Future<void> Function() detail;
  final Future<void> Function()? save, ignore, assign, archive, preview;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey(item.id),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ingestionChannels[item.channel]} · ${ingestionStatuses[item.status]}',
          ),
          Text(
            '接收时间（北京时间）：${item.receivedAt.toUtc().add(const Duration(hours: 8)).toIso8601String().substring(0, 16).replaceAll('T', ' ')}',
          ),
          const SizedBox(height: 8),
          if (item.file != null)
            Text('附件：${item.file!.name} · ${item.file!.size} 字节'),
          Text(item.preview, maxLines: 4, overflow: TextOverflow.ellipsis),
          _actions(),
        ],
      ),
    ),
  );

  Widget _actions() => Wrap(
    spacing: 12,
    children: [
      TextButton(
        onPressed: detail,
        child: Text(item.file == null ? '查看原文' : '查看材料'),
      ),
      if (preview != null)
        TextButton(
          onPressed: preview,
          child: Text(offline ? '查看正文示例' : '提取正文'),
        ),
      if (save != null) OnlineAction(label: '下载原件', run: save!),
      if (item.file != null && offline) const Text('虚构示例，无真实原件'),
      if (archive != null)
        TextButton(onPressed: archive, child: const Text('归档去向')),
      if (assign != null)
        TextButton(onPressed: assign, child: const Text('分类归档')),
      if (ignore != null) OnlineAction(label: '忽略材料', run: ignore!),
    ],
  );
}
