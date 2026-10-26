import 'package:flutter/material.dart';
import '../domain/ingestion.dart';
import 'online_widgets.dart';

class IngestionDetailDialog extends StatefulWidget {
  const IngestionDetailDialog({
    required this.repository,
    required this.id,
    super.key,
  });
  final IngestionRepository repository;
  final String id;
  @override
  State<IngestionDetailDialog> createState() => _IngestionDetailDialogState();
}

class _IngestionDetailDialogState extends State<IngestionDetailDialog> {
  late Future<IngestionItem> _result = _read();
  Future<IngestionItem> _read() {
    final future = widget.repository.detail(widget.id);
    future.ignore();
    return future;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('材料原文'),
    content: SizedBox(
      width: 560,
      height: 360,
      child: OnlineResult(
        future: _result,
        retry: () => setState(() {
          _result = _read();
        }),
        render: (item) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${ingestionChannels[item.channel]} · ${ingestionStatuses[item.status]}',
              ),
              const SizedBox(height: 12),
              if (item.file != null) ...[
                Text('附件：${item.file!.name}'),
                Text('${item.file!.size} 字节 · ${item.file!.mimeType}'),
                const Text('以下是接收说明。文件正文可从材料列表的正文预览入口查看。'),
              ],
              // 纯文本展示，不把文内链接转换为可访问或自动下载的入口。
              SelectableText(item.rawContent!),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
