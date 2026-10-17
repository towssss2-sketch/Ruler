import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/device_files.dart';
import '../domain/documents.dart';
import 'online_widgets.dart';

/// 选择、分类、上传和原票据重试，完整登记后才显示成功。
class DocumentUploadDialog extends StatefulWidget {
  const DocumentUploadDialog({
    required this.caseId,
    required this.repository,
    required this.files,
    this.previous,
    super.key,
  });
  final String caseId;
  final DocumentRepository repository;
  final DeviceFiles files;
  final CaseDocument? previous;
  @override
  State<DocumentUploadDialog> createState() => _DocumentUploadDialogState();
}

class _DocumentUploadDialogState extends State<DocumentUploadDialog> {
  PreparedUpload? _prepared;
  DocumentUpload? _upload;
  late String _category = widget.previous?.category ?? 'OTHER';
  bool _busy = false;
  double? _progress;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await widget.files.pick();
      if (!mounted) {
        await _release(file);
        return;
      }
      if (file != null) {
        await _release(_prepared);
        _prepared = file;
      }
    } catch (error) {
      if (mounted) _error = onlineError(error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        await _release(_prepared);
      }
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _upload ??= widget.repository.beginUpload(
        widget.caseId,
        _prepared!.source,
        _category,
        previousId: widget.previous?.id,
      );
      await _upload!.resume(
        onProgress: (sent, total) {
          if (mounted) {
            setState(() => _progress = total > 0 ? sent / total : null);
          }
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _error = onlineError(error);
    } finally {
      _busy = false;
      if (mounted) {
        setState(() {});
      } else {
        await _release(_prepared);
      }
    }
  }

  @override
  void dispose() {
    _upload?.cancel();
    if (!_busy) {
      unawaited(_release(_prepared));
    }
    super.dispose();
  }

  Future<void> _release(PreparedUpload? file) async {
    try {
      await file?.dispose();
    } catch (_) {
      // 无法删除的副本仅留在系统私有缓存，不回显本机路径。
    }
  }

  void _dismiss() {
    _upload?.cancel();
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.previous == null ? '上传案件文件' : '上传新版本'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(child: _content()),
    ),
    actions: [
      TextButton(onPressed: _dismiss, child: Text(_busy ? '停止并关闭' : '关闭')),
      FilledButton(
        onPressed: _busy || _prepared == null ? null : _send,
        child: Text(
          _busy
              ? '处理中…'
              : _upload == null
              ? '开始上传'
              : _upload!.bytesUploaded
              ? '重试登记'
              : '重试上传',
        ),
      ),
    ],
  );

  Widget _content() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('支持 PDF、Word、图片、MP4，单个文件不超过 200 MiB。'),
      if (widget.previous != null) Text('原文件：${widget.previous!.name}'),
      OutlinedButton(
        onPressed: _busy || _upload != null ? null : _pick,
        child: const Text('选择设备文件'),
      ),
      if (_prepared != null)
        Text('${_prepared!.source.name} · ${_prepared!.source.size} 字节'),
      DropdownButtonFormField<String>(
        initialValue: _category,
        decoration: const InputDecoration(labelText: '归档分类'),
        isExpanded: true,
        items: documentCategories.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: _busy || _upload != null
            ? null
            : (value) => setState(() => _category = value!),
      ),
      if (_busy) ...[
        const SizedBox(height: 12),
        LinearProgressIndicator(value: _progress),
        Text(_upload == null ? '正在准备文件…' : '正在上传并确认登记…'),
      ],
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_upload?.bytesUploaded == true && _error != null)
        const Text('文件已传输，登记尚未确认。重试只登记原文件，不重复上传。'),
      const Text('关闭会停止本机传输；已经登记的文件可能保留，请刷新列表确认。'),
    ],
  );
}
