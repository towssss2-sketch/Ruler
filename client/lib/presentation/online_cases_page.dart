import '../domain/case_fields.dart';
import '../domain/case_filters.dart';
import 'case_filter_bar.dart';
import 'package:flutter/material.dart';
import '../domain/online.dart';
import 'online_form.dart';
import 'online_tasks_page.dart';
import 'online_widgets.dart';
import 'today_entry.dart';

/// 当前账号的服务端案件列表，搜索和分页均由接口执行。
class OnlineCasesPage extends StatefulWidget {
  const OnlineCasesPage({
    required this.repository,
    required this.logout,
    super.key,
  });
  final OnlineRepository repository;
  final Future<void> Function() logout;
  @override
  State<OnlineCasesPage> createState() => _OnlineCasesPageState();
}

class _OnlineCasesPageState extends State<OnlineCasesPage> {
  final _search = TextEditingController();
  String _keyword = '';
  CaseFilters _filters = const CaseFilters();
  int _page = 1;
  late Future<OnlinePage<OnlineCase>> _result = _read();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load([int? page]) => setState(() {
    _page = page ?? _page;
    _result = _read();
  });

  Future<OnlinePage<OnlineCase>> _read() {
    final future = widget.repository.cases(
      keyword: _keyword,
      page: _page,
      filters: _filters,
    );
    future.ignore();
    return future;
  }

  void _filter(CaseFilters value) {
    _filters = value;
    _load(1);
  }

  Future<void> _create() async {
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (context) => OnlineForm(repository: widget.repository),
    );
    if (saved == true && mounted) _load(1);
  }

  Future<void> _open(OnlineCase item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            OnlineTasksPage(repository: widget.repository, item: item),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('我的测试案件'),
      actions: [
        IconButton(
          tooltip: '今日任务',
          icon: const Icon(Icons.today),
          onPressed: () => openOnlineToday(context, widget.repository),
        ),
        OnlineAction(label: '退出登录', run: widget.logout),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('测试服务 · 已保存数据保留在服务端 · 仅限虚构资料'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    maxLength: 128,
                    decoration: const InputDecoration(labelText: '搜索案号、案由或当事人'),
                    onSubmitted: (_) => _applySearch(),
                  ),
                ),
                IconButton(
                  tooltip: '搜索',
                  onPressed: _applySearch,
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: '刷新案件',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          CaseFilterBar(value: _filters, change: _filter),
          Expanded(
            child: OnlineResult(future: _result, retry: _load, render: _list),
          ),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('新建测试案件'),
    ),
  );

  void _applySearch() {
    _keyword = _search.text.trim();
    _load(1);
  }

  Widget _list(OnlinePage<OnlineCase> result) => Column(
    children: [
      Expanded(
        child: result.items.isEmpty
            ? const Center(child: Text('没有符合条件的测试案件'))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: result.items.length,
                itemBuilder: (context, index) {
                  final item = result.items[index];
                  return ListTile(
                    title: Text(item.caseNo),
                    subtitle: Text(
                      '${item.cause} · ${item.court}\n${caseStages[item.stage]} · ${caseStatuses[item.status]}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(item),
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: onlinePagination(result, _load),
      ),
    ],
  );
}
