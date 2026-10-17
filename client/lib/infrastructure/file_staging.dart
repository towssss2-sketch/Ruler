import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../domain/documents.dart';
import '../domain/online.dart';

/// 私有临时文件；精确长度和摘要都取自同一份快照。
class StagedFile {
  StagedFile._(this.directory, this.file);
  final Directory directory;
  final File file;

  /// 创建独立工作目录，不使用原始文件名构造磁盘路径。
  static Future<StagedFile> create(Directory root) async {
    await root.create(recursive: true);
    final directory = await root.createTemp('ruler-transfer-');
    return StagedFile._(directory, File('${directory.path}/content'));
  }

  /// 分块写入并计算 MD5；短读、超限和取消均拒绝成功。
  Future<String> receive(
    Stream<List<int>> stream,
    int expected,
    bool Function() active,
  ) async {
    if (expected < 1 || expected > maxDocumentBytes) {
      throw const ApiFailure('请选择不超过 200 MiB 的非空文件。');
    }
    final digest = _DigestResult();
    final hash = md5.startChunkedConversion(digest);
    final output = await file.open(mode: FileMode.writeOnly);
    var count = 0;
    try {
      await for (final chunk in stream) {
        count += chunk.length;
        if (!active() || count > expected) {
          throw const ApiFailure('文件已变化、超限或操作已取消。');
        }
        await output.writeFrom(chunk);
        hash.add(chunk);
      }
      if (!active() || count != expected) {
        throw const ApiFailure('文件长度不符或操作已取消。');
      }
      await output.flush();
    } finally {
      hash.close();
      await output.close();
    }
    return base64Encode(digest.value!.bytes);
  }

  /// 删除仅由本实例创建的工作目录；绝不删除用户原文件。
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _DigestResult implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Windows 先完整写入目标目录的临时文件，成功后才替换目标。
Future<void> commitDesktopFile(
  File source,
  String destination,
  bool Function() active,
) async {
  final target = File(destination);
  final temporary = await target.parent.createTemp('.ruler-save-');
  try {
    final staged = File('${temporary.path}/content');
    final output = await staged.open(mode: FileMode.writeOnly);
    try {
      await for (final chunk in source.openRead()) {
        if (!active()) throw const ApiFailure('保存已取消。');
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (!active()) throw const ApiFailure('保存已取消。');
    await staged.rename(target.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}
