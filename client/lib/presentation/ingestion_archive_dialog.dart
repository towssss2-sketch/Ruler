import 'package:flutter/material.dart';
import '../domain/ingestion_archive.dart';
import '../domain/online.dart';
import '../domain/documents.dart';
import 'online_widgets.dart';

class ArchiveDialogResult {
  const ArchiveDialogResult({this.target, this.status});
  final OnlineCase? target;
  final String? status;
}

class IngestionArchiveDialog extends StatefulWidget {
  const IngestionArchiveDialog({
    required this.id,
    required this.repository,
    this.offline = false,
    super.key,
  });
  final String id;
  final IngestionArchive repository;
  final bool offline;
  @override
  State<IngestionArchiveDialog> createState() => _IngestionArchiveDialogState();
}

class _IngestionArchiveDialogState extends State<IngestionArchiveDialog> {
  bool _busy = false, _confirming = false;
  bool get _working => _busy || _confirming;
  String? _error;
  late Future<ArchiveLocation> _result = _read();
  Future<ArchiveLocation> _read() {
    final result = widget.repository.locate(widget.id);
    result.ignore();
    return result;
  }

  void _reload() => setState(() {
    _error = null;
    _result = _read();
  });
  Future<void> _withdraw(ArchiveLocation view) async {
    if (_working) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('撤回这次归档？'),
          content: Text(
            widget.offline
                ? '将移除案件内的虚构示例，材料回到待定区，可重新选择案件和分类。'
                : '案件文件将移出列表，原件回到待定区。历史副本仍保留，不释放容量；重新归档将新增一份副本。已有下载链接最长十分钟内仍可能有效。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认撤回'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      final status = await widget.repository.withdraw(widget.id, view.receipt!);
      if (mounted) Navigator.pop(context, ArchiveDialogResult(status: status));
    } catch (error) {
      if (mounted) setState(() => _error = onlineError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: AlertDialog(
      title: const Text('归档去向'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) const LinearProgressIndicator(),
              IgnorePointer(
                ignoring: _working,
                child: OnlineResult(
                  future: _result,
                  retry: _reload,
                  render: _view,
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
  Widget _view(ArchiveLocation view) {
    if (view.state == 'UNASSIGNED') return const Text('材料当前未归档，请返回列表刷新。');
    if (view.state == 'UNAVAILABLE') {
      return const Text('归档案件或文件已不可用，请返回案件列表核对。');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(view.target!.caseNo),
        Text(view.target!.court),
        Text('文件分类：${documentCategories[view.receipt!.category]}'),
        if (widget.offline) const Text('仅本次虚构体验，无真实原件。'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy
              ? null
              : () => Navigator.pop(
                  context,
                  ArchiveDialogResult(target: view.target),
                ),
          child: const Text('打开所属案件'),
        ),
        if (view.canWithdraw)
          OutlinedButton(
            onPressed: _working ? null : () => _withdraw(view),
            child: const Text('撤回待定区'),
          )
        else
          const Text('文件存在其他保留版本或状态不支持，暂不能撤回。'),
        TextButton(
          onPressed: _working ? null : _reload,
          child: const Text('刷新去向'),
        ),
      ],
    );
  }
}
