import 'package:flutter/material.dart';
import '../domain/ingestion_assignment.dart';
import '../domain/online.dart';
import 'online_widgets.dart';

class IngestionCasePicker extends StatefulWidget {
  const IngestionCasePicker({required this.repository, super.key});
  final IngestionAssignment repository;
  @override
  State<IngestionCasePicker> createState() => _IngestionCasePickerState();
}

class _IngestionCasePickerState extends State<IngestionCasePicker> {
  final _search = TextEditingController();
  String _keyword = '';
  int _page = 1;
  late Future<OnlinePage<OnlineCase>> _result = _read();
  Future<OnlinePage<OnlineCase>> _read() {
    final future = widget.repository.cases(keyword: _keyword, page: _page);
    future.ignore();
    return future;
  }

  void _load([int? page]) => setState(() {
    _page = page ?? _page;
    _result = _read();
  });
  void _find() {
    _keyword = _search.text.trim();
    _load(1);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择归档案件'),
    content: SizedBox(
      width: 520,
      height: 420,
      child: Column(
        children: [
          TextField(
            controller: _search,
            onSubmitted: (_) => _find(),
            decoration: InputDecoration(
              labelText: '搜索案号、案由或当事人',
              suffixIcon: IconButton(
                tooltip: '搜索案件',
                onPressed: _find,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: OnlineResult(future: _result, retry: _load, render: _list),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
  Widget _list(OnlinePage<OnlineCase> result) => Column(
    children: [
      Expanded(
        child: result.items.isEmpty
            ? const Center(child: Text('没有匹配案件，请先新建案件或修改搜索。'))
            : ListView(
                children: [
                  for (final item in result.items)
                    ListTile(
                      title: Text(item.caseNo),
                      subtitle: Text('${item.court}\n${item.cause}'),
                      isThreeLine: true,
                      onTap: () => Navigator.pop(context, item),
                    ),
                ],
              ),
      ),
      onlinePagination(result, _load),
    ],
  );
}
