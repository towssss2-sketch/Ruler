import 'package:flutter/material.dart';
import '../domain/today.dart';
import 'today_calendar.dart';
import 'today_task_card.dart';
import 'online_widgets.dart';

/// 在线/离线共用显示与操作状态；仓库回调严格分离，刷新不重复写入。
class TodayPage extends StatefulWidget {
  const TodayPage({
    required this.load,
    required this.complete,
    required this.openCase,
    this.offline = false,
    super.key,
  });
  final Future<TodaySnapshot> Function(int page) load;
  final Future<void> Function(TodayTask task) complete, openCase;
  final bool offline;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> with WidgetsBindingObserver {
  int _page = 1;
  bool _busy = false;
  late Future<TodaySnapshot> _result = _read();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load(1);
  }

  Future<TodaySnapshot> _read() {
    final future = widget.load(_page);
    future.ignore();
    return future;
  }

  void _load([int? page]) => setState(() {
    _page = page ?? _page;
    _result = _read();
  });
  Future<void> _complete(TodayTask task) async {
    if (_busy) return;
    if (task.isDeadline && !await confirmTodayDeadline(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.complete(task);
      if (mounted) _load(1);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(TodayTask task) async {
    await widget.openCase(task);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('今日任务汇总'),
        actions: [
          IconButton(
            tooltip: '刷新今日清单',
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
  Widget _list(TodaySnapshot result) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(widget.offline ? '虚构体验 · 仅本次内存数据' : '测试服务 · 仅限虚构资料'),
            const Text('全部案件的未完成任务：已确认期间优先，其次逾期、今日到期。普通未来任务及未设日期任务不在此列。'),
            TodayCalendar(date: result.date),
            if (result.items.isEmpty)
              Text(result.total == 0 ? '暂无需要今日处理的任务' : '本页已无任务，请返回上一页或刷新'),
            for (final task in result.items)
              TodayTaskCard(
                key: ValueKey(task.id),
                task: task,
                date: result.date,
                complete: () => _complete(task),
                openCase: () => _open(task),
              ),
          ],
        ),
      ),
      onlinePagination(result, (page) => _load(page)),
    ],
  );
}
