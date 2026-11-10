import 'package:flutter/material.dart';
import '../domain/documents.dart';
import '../domain/saved_classification.dart';
import 'online_widgets.dart';

Future<void> showSavedClassification(
  BuildContext context,
  String id,
  String attemptId,
  SavedClassifications repository,
  bool offline,
) => showDialog<void>(
  context: context,
  useRootNavigator: false,
  builder: (_) => SavedClassificationDialog(
    id: id,
    attemptId: attemptId,
    repository: repository,
    offline: offline,
  ),
);

class SavedClassificationDialog extends StatefulWidget {
  const SavedClassificationDialog({
    required this.id,
    required this.attemptId,
    required this.repository,
    this.offline = false,
    super.key,
  });
  final String id, attemptId;
  final SavedClassifications repository;
  final bool offline;
  @override
  State<SavedClassificationDialog> createState() =>
      _SavedClassificationDialogState();
}

class _SavedClassificationDialogState extends State<SavedClassificationDialog> {
  late Future<SavedClassification> _result = _read();
  Future<SavedClassification> _read() {
    final result = widget.repository.classification(
      widget.id,
      widget.attemptId,
    );
    result.ignore();
    return result;
  }

  void _refresh() => setState(() {
    _result = _read();
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.offline ? '虚构分类建议' : '历史分类建议'),
    content: SizedBox(
      width: 520,
      height: 320,
      child: SingleChildScrollView(
        child: OnlineResult(future: _result, retry: _refresh, render: _content),
      ),
    ),
    actions: [
      TextButton(onPressed: _refresh, child: const Text('刷新分类')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('返回记录'),
      ),
    ],
  );

  Widget _content(SavedClassification value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.offline) const Text('仅为本次虚构体验的分类记录，关闭应用清除，没有解析真实文件。'),
      if (value.state == 'NOT_RECORDED')
        const Text('这次提取未保存分类记录。旧版历史不会补填，可返回材料页重新查看正文。'),
      if (value.state == 'NOT_AVAILABLE')
        const Text('这次提取尚无可用的分类结果，请返回提取记录查看处理状态。'),
      if (value.state == 'RECORDED') ...[
        Text(
          value.category == null
              ? '没有确定的分类建议'
              : '建议分类：${documentCategories[value.category]}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(switch (value.reason) {
          'TITLE_MATCH' => '识别到明确的文书标题。',
          'CONFLICTING_TITLES' => '标题提示多个类别，请人工核对后选择。',
          _ => '未识别到明确标题，请人工选择分类。',
        }),
        const Text('识别规则：标题规则 v1'),
      ],
      const SizedBox(height: 12),
      const Text('这是该次提取的建议，不代表当前归档分类。仍需你核对材料并确认分类与案件。'),
      const Text('查看或刷新不会重新提取，也不会自动归档。'),
    ],
  );
}
