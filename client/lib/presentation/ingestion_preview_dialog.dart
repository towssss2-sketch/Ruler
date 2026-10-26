import 'package:flutter/material.dart';
import '../domain/documents.dart';
import '../domain/ingestion_preview.dart';
import '../domain/online.dart';

class IngestionPreviewDialog extends StatefulWidget {
  const IngestionPreviewDialog({
    required this.id,
    required this.name,
    required this.repository,
    this.offline = false,
    this.canAssign = false,
    super.key,
  });
  final String id, name;
  final IngestionPreview repository;
  final bool offline, canAssign;
  @override
  State<IngestionPreviewDialog> createState() => _IngestionPreviewDialogState();
}

class _IngestionPreviewDialogState extends State<IngestionPreviewDialog> {
  IngestionPreviewResult? _result;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.repository.preview(widget.id);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure ? error.message : '正文提取未完成，请稍后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _result = null;
    _error = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.offline ? '虚构正文示例' : '文件正文预览'),
    content: SizedBox(
      width: 600,
      height: 440,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name),
            const SizedBox(height: 8),
            Text(
              widget.offline
                  ? '预置示例，不读取设备或解析真实文件。'
                  : '仅本次查看，不保存到客户端；请对照原件核对提取结果。',
            ),
            const SizedBox(height: 12),
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              const Text('正在处理，请稍候。关闭仅退出预览，已提交的处理可能继续。'),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_result != null) ..._content(_result!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      if (!_busy && (_error != null || _result?.retryable == true))
        OutlinedButton(onPressed: _load, child: const Text('重试提取')),
      if (!_busy && _result?.text != null)
        TextButton(
          onPressed: _load,
          child: Text(widget.offline ? '重看示例' : '重新提取'),
        ),
      if (!_busy && widget.canAssign && _result?.suggestion?.category != null)
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _result!.suggestion!.category),
          child: const Text('按建议选择分类'),
        ),
    ],
  );

  List<Widget> _content(IngestionPreviewResult result) {
    if (result.reason != null) {
      return [
        Text(previewReasons[result.reason]!),
        const SizedBox(height: 12),
        const Text('原件和已有归档未改变。返回材料列表后可下载原件或手动选择分类。'),
      ];
    }
    final suggestion = result.suggestion!;
    return [
      Text(
        suggestion.category == null
            ? suggestion.reason == 'CONFLICTING_TITLES'
                  ? '标题存在冲突，请手动选择分类。'
                  : '没有明确的分类建议，请手动选择。'
            : '建议分类：${documentCategories[suggestion.category]}',
      ),
      const Text('建议需要人工核对；不自动选择案件或生成法律期限。'),
      if (suggestion.caseNumbers.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('候选案号（尚未匹配案件）'),
        for (final number in suggestion.caseNumbers) Text(number),
        if (suggestion.truncated) const Text('案号较多，仅显示前 10 个，请核对完整原件。'),
      ],
      const SizedBox(height: 16), const Text('正文'), const SizedBox(height: 8),
      // 纯文本显示，不执行 HTML、不创建链接入口，也不自动写入剪贴板。
      SelectableText(result.text!),
    ];
  }
}
