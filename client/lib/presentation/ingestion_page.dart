import 'package:flutter/material.dart';
import '../domain/ingestion.dart';
import '../domain/ingestion_assignment.dart';
import 'ingestion_assign_dialog.dart';
import '../domain/ingestion_files.dart';
import '../domain/device_files.dart';
import 'ingestion_upload_dialog.dart';
import '../domain/online.dart';
import 'ingestion_detail.dart';
import 'ingestion_editor.dart';
import 'online_widgets.dart';

class IngestionPage extends StatefulWidget {
  const IngestionPage({
    required this.repository,
    this.offline = false,
    this.attachments,
    this.files,
    this.addExample,
    this.assignment,
    super.key,
  });
  final IngestionRepository repository;
  final bool offline;
  final IngestionAssignment? assignment;
  final IngestionFiles? attachments;
  final DeviceFiles? files;
  final Future<IngestionReceipt> Function()? addExample;
  @override
  State<IngestionPage> createState() => _IngestionPageState();
}

class _IngestionPageState extends State<IngestionPage> {
  int _page = 1;
  bool _history = false, _busy = false, _confirming = false;
  late Future<OnlinePage<IngestionItem>> _result = _read();
  Future<OnlinePage<IngestionItem>> _read() {
    final future = widget.repository.list(page: _page, history: _history);
    future.ignore();
    return future;
  }

  void _load([int? page]) => setState(() {
    _page = page ?? _page;
    _result = _read();
  });
  Future<void> _receive() async {
    final receipt = await showDialog<IngestionReceipt>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => IngestionEditor(repository: widget.repository),
    );
    if (receipt == null || !mounted) return;
    _history = receipt.status != 'PENDING_MATCH';
    _load(1);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(receipt.message)));
  }

  Future<void> _upload() async {
    final receipt = await showDialog<IngestionFileReceipt>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => IngestionUploadDialog(
        repository: widget.attachments!,
        files: widget.files!,
      ),
    );
    if (!mounted) return;
    if (receipt != null) _history = receipt.status != 'PENDING_MATCH';
    _load(1); // 关闭时完成响应可能尚未到达，也独立重读确认。
    if (receipt != null) _notice(receipt.message);
  }

  Future<void> _example() async {
    final receipt = await widget.addExample!();
    if (!mounted) return;
    _history = receipt.status != 'PENDING_MATCH';
    _load(1);
    _notice(
      receipt.duplicate
          ? '虚构文件示例已存在，当前${ingestionStatuses[receipt.status]}。'
          : '已添加虚构文件示例，没有上传真实文件。',
    );
  }

  void _notice(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save(IngestionItem item) async {
    ScaffoldMessenger.of(context).clearSnackBars();
    final file = item.file!;
    final saved = await widget.files!.save(
      DownloadSource(
        name: file.name,
        size: file.size,
        download: (consume) =>
            widget.attachments!.download(item.id, file, consume),
      ),
    );
    if (mounted) _notice(saved ? '文件已保存到所选位置。' : '已取消保存。');
  }

  Future<void> _ignore(IngestionItem item) async {
    if (_busy || _confirming) return;
    _confirming = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('忽略这份材料？'),
          content: const Text('将从待定区移出，原文仍保留在归集历史中。当前版本不提供撤销忽略。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认忽略'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      await widget.repository.ignore(item.id);
      if (mounted) _load(1);
    } finally {
      _confirming = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(IngestionItem item) async {
    final notice = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => IngestionAssignDialog(
        item: item,
        repository: widget.assignment!,
        offline: widget.offline,
      ),
    );
    if (!mounted) return;
    if (notice != null) _history = true;
    _load(1);
    if (notice != null) _notice(notice);
  }

  Future<void> _detail(IngestionItem item) => showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (_) =>
        IngestionDetailDialog(repository: widget.repository, id: item.id),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('材料待定区'),
        actions: [
          IconButton(
            tooltip: '刷新材料',
            onPressed: _busy ? null : () => _load(1),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: IgnorePointer(
          ignoring: _busy,
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              _header(),
              Expanded(
                child: OnlineResult(
                  future: _result,
                  retry: _load,
                  render: _list,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        Text(widget.offline ? '虚构体验 · 关闭应用清除' : '测试服务 · 仅限虚构资料'),
        Text(
          widget.offline
              ? '可添加虚构文字或文件示例；不读取设备文件。'
              : '手动接收文字或文件；待定附件可选择分类并归入案件。',
        ),
        _actions(),
      ],
    ),
  );

  Widget _actions() => Wrap(
    spacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ChoiceChip(
        label: const Text('待定材料'),
        selected: !_history,
        onSelected: (_) {
          _history = false;
          _load(1);
        },
      ),
      ChoiceChip(
        label: const Text('归集历史'),
        selected: _history,
        onSelected: (_) {
          _history = true;
          _load(1);
        },
      ),
      if (widget.attachments != null && widget.files != null)
        OutlinedButton.icon(
          onPressed: _upload,
          icon: const Icon(Icons.upload_file),
          label: const Text('导入设备文件'),
        ),
      if (widget.addExample != null)
        OutlinedButton.icon(
          onPressed: _example,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('添加虚构文件示例'),
        ),
      OutlinedButton.icon(
        onPressed: _receive,
        icon: const Icon(Icons.add),
        label: const Text('粘贴转发文字'),
      ),
    ],
  );

  Widget _list(OnlinePage<IngestionItem> result) => Column(
    children: [
      Expanded(
        child: result.items.isEmpty
            ? Center(
                child: Text(
                  result.total > 0
                      ? '本页已无材料，请返回上一页或刷新'
                      : _history
                      ? '暂无归集历史'
                      : '暂无待定材料',
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: result.items.length,
                itemBuilder: (context, index) => _card(result.items[index]),
              ),
      ),
      onlinePagination(result, _load),
    ],
  );

  Widget _card(IngestionItem item) => Card(
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
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => _detail(item),
                child: Text(item.file == null ? '查看原文' : '查看材料'),
              ),
              if (item.file != null &&
                  widget.attachments != null &&
                  widget.files != null)
                OnlineAction(label: '下载原件', run: () => _save(item)),
              if (item.file != null && widget.offline) const Text('虚构示例，无真实原件'),
              if (item.status == 'PENDING_MATCH' &&
                  item.file != null &&
                  widget.assignment != null)
                TextButton(
                  onPressed: () => _assign(item),
                  child: const Text('分类归档'),
                ),
              if (item.status == 'PENDING_MATCH')
                OnlineAction(label: '忽略材料', run: () => _ignore(item)),
            ],
          ),
        ],
      ),
    ),
  );
}
