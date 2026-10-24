import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/device_files.dart';
import '../domain/ingestion_files.dart';
import 'online_widgets.dart';

/// 无需案件的选择、上传和原票据重试，完整登记后才显示成功。
class IngestionUploadDialog extends StatefulWidget {
  const IngestionUploadDialog({
    required this.repository,
    required this.files,
    super.key,
  });
  final IngestionFiles repository;
  final DeviceFiles files;
  @override
  State<IngestionUploadDialog> createState() => _IngestionUploadDialogState();
}

class _IngestionUploadDialogState extends State<IngestionUploadDialog> {
  PreparedUpload? _prepared;
  IngestionUpload? _upload;
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
      _upload ??= widget.repository.begin(_prepared!.source);
      final receipt = await _upload!.resume(
        onProgress: (sent, total) {
          if (mounted) {
            setState(() => _progress = total > 0 ? sent / total : null);
          }
        },
      );
      if (mounted) Navigator.pop(context, receipt);
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
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('文件暂存到待定区'),
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
    ),
  );

  Widget _content() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('支持 PDF、Word、图片、MP4，单个文件不超过 200 MiB。无需先选择案件。'),
      OutlinedButton(
        onPressed: _busy || _upload != null ? null : _pick,
        child: const Text('选择设备文件'),
      ),
      if (_prepared != null)
        Text('${_prepared!.source.name} · ${_prepared!.source.size} 字节'),
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
      const Text('关闭会停止本机传输；已经接收的文件可能保留，请刷新待定区确认。'),
    ],
  );
}
