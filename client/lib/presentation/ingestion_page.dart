import 'package:flutter/material.dart';
import '../domain/ingestion.dart';
import '../domain/online.dart';
import 'ingestion_detail.dart';
import 'ingestion_editor.dart';
import 'online_widgets.dart';

class IngestionPage extends StatefulWidget {
  const IngestionPage({
    required this.repository,
    this.offline = false,
    super.key,
  });
  final IngestionRepository repository;
  final bool offline;
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
        const Text('手动接收微信文字。文件导入、自动分类和指派案件尚未开放。'),
        Wrap(
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
            OutlinedButton.icon(
              onPressed: _receive,
              icon: const Icon(Icons.add),
              label: const Text('粘贴转发文字'),
            ),
          ],
        ),
      ],
    ),
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
          Text(item.preview, maxLines: 4, overflow: TextOverflow.ellipsis),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => _detail(item),
                child: const Text('查看原文'),
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
