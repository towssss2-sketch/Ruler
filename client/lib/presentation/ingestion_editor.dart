import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/ingestion.dart';
import 'online_widgets.dart';

class IngestionEditor extends StatefulWidget {
  const IngestionEditor({required this.repository, super.key});
  final IngestionRepository repository;
  @override
  State<IngestionEditor> createState() => _IngestionEditorState();
}

class _IngestionEditorState extends State<IngestionEditor> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _error = ingestionTextError(_text.text));
    if (_error != null) return;
    setState(() => _busy = true);
    try {
      final receipt = await widget.repository.receive(_text.text);
      if (mounted) Navigator.pop(context, receipt);
    } catch (error) {
      if (mounted) setState(() => _error = onlineError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('手动转发微信文字'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('粘贴虚构文字，保存后进入待定区。仅接收文字，不下载链接、不接收附件、不自动分类。'),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                enabled: !_busy,
                minLines: 4,
                maxLines: 8,
                maxLength: 10000,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                decoration: const InputDecoration(labelText: '转发文字（仅虚构资料）'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? '保存中…' : '保存到待定区'),
        ),
      ],
    ),
  );
}
