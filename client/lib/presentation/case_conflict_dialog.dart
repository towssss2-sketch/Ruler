import 'package:flutter/material.dart';
import '../domain/case_conflict.dart';
import '../domain/online.dart';
import 'online_widgets.dart';

/// 仅检查已保存名单；失败与未命中分别展示，不输出自动法律结论。
class CaseConflictDialog extends StatefulWidget {
  const CaseConflictDialog({required this.load, super.key});
  final Future<OnlinePage<CaseConflict>> Function(int page) load;
  @override
  State<CaseConflictDialog> createState() => _CaseConflictDialogState();
}

class _CaseConflictDialogState extends State<CaseConflictDialog> {
  int _page = 1;
  late Future<OnlinePage<CaseConflict>> _result = _read();
  Future<OnlinePage<CaseConflict>> _read() {
    final pending = Future<OnlinePage<CaseConflict>>.sync(
      () => widget.load(_page),
    );
    pending.ignore();
    return pending;
  }

  void _load([int? page]) => setState(() {
    _page = page ?? _page;
    _result = _read();
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('利益冲突检查 · 待人工核对'),
    content: SizedBox(
      width: 560,
      height: 420,
      child: Column(
        children: [
          const Text(
            '按已保存当事人姓名查询当前账号的历史案件，包含已删除记录。相似度 ≥ 60% 仅为姓名相似提示，不代表存在利益冲突；未命中也不代表不存在利益冲突。',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: OnlineResult(future: _result, retry: _load, render: _list),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => _load(1), child: const Text('重新检查')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );

  Widget _list(OnlinePage<CaseConflict> result) => Column(
    children: [
      Expanded(
        child: result.items.isEmpty
            ? Center(
                child: Text(
                  result.total == 0
                      ? '本次未命中相似姓名的案件，请继续人工核对。'
                      : '本页没有记录，请返回上一页或重新检查。',
                ),
              )
            : ListView.builder(
                itemCount: result.items.length,
                itemBuilder: (_, index) {
                  final item = result.items[index];
                  return ListTile(
                    title: Text(item.caseNo),
                    subtitle: Text(
                      '${item.court}\n${item.deleted ? '已删除的历史案件' : '历史案件'} · 姓名相似度 ${(item.similarity * 100).toStringAsFixed(1)}%',
                    ),
                  );
                },
              ),
      ),
      onlinePagination(result, _load),
    ],
  );
}
