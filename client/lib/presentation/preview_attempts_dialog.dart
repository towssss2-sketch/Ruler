import 'package:flutter/material.dart';
import '../domain/preview_attempts.dart';
import '../domain/ingestion_preview.dart';
import '../domain/online.dart';
import 'online_widgets.dart';

/// 返回 true 仅表示用户明确要求再次提取，不会自动重放未知结果的 POST。
Future<bool?> showPreviewAttempts(
  BuildContext context,
  String id,
  PreviewAttempts repository,
  bool offline,
) => showDialog<bool>(
  context: context,
  useRootNavigator: false,
  builder: (_) =>
      PreviewAttemptsDialog(id: id, repository: repository, offline: offline),
);

class PreviewAttemptsDialog extends StatefulWidget {
  const PreviewAttemptsDialog({
    required this.id,
    required this.repository,
    this.offline = false,
    super.key,
  });
  final String id;
  final PreviewAttempts repository;
  final bool offline;
  @override
  State<PreviewAttemptsDialog> createState() => _PreviewAttemptsDialogState();
}

class _PreviewAttemptsDialogState extends State<PreviewAttemptsDialog> {
  int _page = 1;
  late Future<OnlinePage<PreviewAttempt>> _result = _read();
  Future<OnlinePage<PreviewAttempt>> _read() {
    final result = widget.repository.attempts(widget.id, page: _page);
    result.ignore();
    return result;
  }

  void _load([int? page]) => setState(() {
    _page = page ?? _page;
    _result = _read();
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.offline ? '虚构提取记录' : '正文提取记录'),
    content: SizedBox(
      width: 600,
      height: 440,
      child: OnlineResult(future: _result, retry: _load, render: _content),
    ),
    actions: [
      TextButton(onPressed: () => _load(1), child: const Text('刷新记录')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );

  Widget _content(OnlinePage<PreviewAttempt> result) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.offline
              ? '仅记录本次虚构体验，关闭应用清除；没有解析真实文件。'
              : '只保存处理状态，不保存提取正文。查看记录不会重新提取或改变归档。',
        ),
        const SizedBox(height: 12),
        if (result.items.isEmpty)
          Text(result.total == 0 ? '尚无提取记录' : '本页没有记录，请返回上一页'),
        for (final item in result.items) _item(item),
        onlinePagination(result, _load),
        if (result.page == 1 &&
            result.items.isNotEmpty &&
            result.items.first.retryable)
          OutlinedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.offline ? '重新查看示例' : '重新提取正文'),
          ),
      ],
    ),
  );

  Widget _item(PreviewAttempt item) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          previewAttemptStatuses[item.status]!,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('开始（北京时间）：${_time(item.startedAt)}'),
        if (item.finishedAt != null)
          Text('结束（北京时间）：${_time(item.finishedAt!)}'),
        if (item.reason != null) Text(previewReasons[item.reason]!),
        if (item.status == 'RUNNING')
          const Text('请稍后刷新。长时间未完成时，系统会标记中断，再由你重新提取。'),
        if (item.status == 'INTERRUPTED')
          const Text('在允许的时间内未确认完成，可能因服务中断。原件保留，可重新提取。'),
        if (item.status == 'SUCCEEDED')
          const Text('本次提取完成，不代表已归档。再次查看正文需要重新提取。'),
      ],
    ),
  );

  String _time(DateTime value) => value
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 19)
      .replaceAll('T', ' ');
}
