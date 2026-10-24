import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import '../domain/device_files.dart';
import '../domain/documents.dart';
import '../domain/online.dart';
import 'document_wire.dart';
import 'file_staging.dart';

/// 系统选择器和保存适配器，不申请全盘读取权限。
class SystemFiles implements DeviceFiles {
  static const _channel = MethodChannel('ruler/device_files');
  bool _closed = false;
  bool get _active => !_closed;

  Future<Directory> _root() async => Platform.isAndroid
      ? Directory((await _channel.invokeMethod<String>('temporaryRoot'))!)
      : Directory.systemTemp;

  @override
  Future<PreparedUpload?> pick() async {
    XFile? selected;
    StagedFile? staged;
    try {
      selected = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: '案件材料',
            extensions: mimeExtensions.keys.toList(),
            mimeTypes: mimeExtensions.values.toSet().toList(),
          ),
        ],
      );
      if (selected == null || !_active) return null;
      final size = await selected.length();
      final mime = mimeExtensions[selected.name.split('.').last.toLowerCase()];
      validateFileMetadata(selected.name, mime ?? '', size);
      staged = await StagedFile.create(await _root());
      final digest = await staged.receive(
        selected.openRead(),
        size,
        () => _active,
      );
      if (!_active) throw const ApiFailure('选择已取消。');
      final prepared = _Prepared(
        staged,
        UploadSource(
          name: selected.name,
          mimeType: mime!,
          size: size,
          md5: digest,
          open: staged.file.openRead,
        ),
      );
      staged = null;
      return prepared;
    } catch (_) {
      throw const ApiFailure('无法准备文件，请选择不超过 200 MiB 的非空 PDF、Word、图片或 MP4。');
    } finally {
      await staged?.dispose();
      if (Platform.isAndroid && selected != null) {
        await _channel.invokeMethod<void>('releaseSelection', {
          'path': selected.path,
        });
      }
    }
  }

  @override
  Future<bool> save(DownloadSource source) async {
    StagedFile? staged;
    try {
      if (!_active) return false;
      staged = await StagedFile.create(await _root());
      final target = staged;
      await source.download((stream) async {
        await target.receive(stream, source.size, () => _active);
      });
      if (!_active) return false;
      final name = safeSaveName(source.name);
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('save', {
              'path': staged.file.path,
              'name': name,
              'mime':
                  mimeExtensions[name.split('.').last.toLowerCase()] ??
                  'application/octet-stream',
            }) ??
            false;
      }
      final destination = await getSaveLocation(suggestedName: name);
      if (destination == null || !_active) return false;
      await commitDesktopFile(staged.file, destination.path, () => _active);
      return true;
    } catch (_) {
      throw const ApiFailure('保存未完成，请检查可用空间和目标位置是否留下不完整文件，再重试。');
    } finally {
      await staged?.dispose();
    }
  }

  @override
  void close() {
    _closed = true;
    if (Platform.isAndroid) {
      unawaited(
        _channel.invokeMethod<void>('cancel').catchError((Object _) {}),
      );
    }
  }
}

class _Prepared implements PreparedUpload {
  _Prepared(this.staged, this.source);
  final StagedFile staged;
  @override
  final UploadSource source;
  @override
  Future<void> dispose() => staged.dispose();
}

/// 服务端名称仅作为建议名，不允许目录、控制字符或 Windows 保留名。
String safeSaveName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (cleaned.isEmpty ||
      cleaned.length > 180 ||
      RegExp(
        r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
        caseSensitive: false,
      ).hasMatch(cleaned)) {
    return '案件文件.bin';
  }
  return cleaned;
}
