import 'package:flutter/material.dart';
import '../domain/ingestion_assignment.dart';
import '../domain/online.dart';
import 'online_widgets.dart';
import '../domain/case_fields.dart';

class IngestionCasePicker extends StatefulWidget {
  const IngestionCasePicker({
    required this.repository,
    this.caseNumbers = const [],
    super.key,
  });
  final IngestionAssignment repository;
  final List<String> caseNumbers;
  @override
  State<IngestionCasePicker> createState() => _IngestionCasePickerState();
}

class _IngestionCasePickerState extends State<IngestionCasePicker> {
  final _search = TextEditingController();
  String _keyword = '';
  String? _caseNo;
  int _page = 1;
  late Future<OnlinePage<OnlineCase>> _result = _read();
  Future<OnlinePage<OnlineCase>> _read() {
    final future = widget.repository.cases(
      keyword: _keyword,
      page: _page,
      caseNo: _caseNo,
    );
    future.ignore();
    return future;
  }

  void _load([int? page]) => setState(() {
    _page = page ?? _page;
    _result = _read();
  });
  void _find() {
    _caseNo = null;
    _keyword = _search.text.trim();
    _load(1);
  }

  void _exact(String? number) {
    _caseNo = number;
    _keyword = '';
    _search.clear();
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.caseNumbers.isNotEmpty) ..._candidates(),
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
            OnlineResult(future: _result, retry: _load, render: _list),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );

  List<Widget> _candidates() => [
    const Text('点击正文案号精确查找本人案件；仍需核对法院后选择。'),
    SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final number in widget.caseNumbers)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('查找 $number'),
                selected: _caseNo == number,
                onSelected: (_) => _exact(number),
              ),
            ),
        ],
      ),
    ),
    if (_caseNo != null)
      TextButton(onPressed: () => _exact(null), child: const Text('清除案号条件')),
  ];
  Widget _list(OnlinePage<OnlineCase> result) => Column(
    children: [
      if (result.items.isEmpty)
        Center(
          child: Text(
            _caseNo == null
                ? '没有匹配案件，请先新建案件或修改搜索。'
                : '本人案件中没有这个完整案号；请核对原件，或用搜索框改选案件。',
          ),
        )
      else ...[
        for (final item in result.items)
          ListTile(
            title: Text(item.caseNo),
            subtitle: Text(
              '${item.court} · ${caseStatuses[item.status]}\n${item.cause}',
            ),
            isThreeLine: true,
            onTap: () => Navigator.pop(context, item),
          ),
      ],
      onlinePagination(result, _load),
    ],
  );
}
