import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/file_staging.dart';
import 'package:ruler_client/infrastructure/system_files.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('ruler-test-'),
  );
  tearDown(() async => root.delete(recursive: true));

  snapshotTests(() => root);
  saveTests(() => root);
}

void snapshotTests(Directory Function() directory) {
  Directory getRoot() => directory();
  test('快照摘要取自实际复制的字节，改动原文件不改变快照', () async {
    final original = await File(
      '${getRoot().path}/original.pdf',
    ).writeAsString('abc');
    final staged = await StagedFile.create(getRoot());
    final digest = await staged.receive(original.openRead(), 3, () => true);
    await original.writeAsString('changed');
    expect(digest, 'kAFQmDzST7DWlj99KOF/cg==');
    expect(await staged.file.readAsString(), 'abc');
    await staged.dispose();
    expect(await staged.directory.exists(), false);
    expect(await original.readAsString(), 'changed');
  });
  for (final size in [0, 2, 4, 209715201]) {
    test('拒绝空文件、长度变化和超限声明 $size', () async {
      final staged = await StagedFile.create(getRoot());
      await expectLater(
        staged.receive(Stream.value([1, 2, 3]), size, () => true),
        throwsA(isA<ApiFailure>()),
      );
      await staged.dispose();
      expect(await staged.directory.exists(), false);
    });
  }
  test('取消快照拒绝写入成功并可清理', () async {
    final staged = await StagedFile.create(getRoot());
    await expectLater(
      staged.receive(Stream.value([1]), 1, () => false),
      throwsA(isA<ApiFailure>()),
    );
    await staged.dispose();
  });
}

void saveTests(Directory Function() directory) {
  Directory getRoot() => directory();
  test('保存取消保留目标旧内容，成功才替换并删除中间文件', () async {
    final source = await File('${getRoot().path}/source').writeAsString('new');
    final target = await File(
      '${getRoot().path}/destination',
    ).writeAsString('old');
    await expectLater(
      commitDesktopFile(source, target.path, () => false),
      throwsA(isA<ApiFailure>()),
    );
    expect(await target.readAsString(), 'old');
    await commitDesktopFile(source, target.path, () => true);
    expect(await target.readAsString(), 'new');
    expect(
      await getRoot().list().where((entry) => entry is Directory).length,
      0,
    );
  });
  test('建议保存名不能穿越目录或使用 Windows 保留名', () {
    expect(safeSaveName('../测试?.pdf'), '.._测试_.pdf');
    expect(safeSaveName('NUL.pdf'), '案件文件.bin');
    expect(safeSaveName('CON'), '案件文件.bin');
    expect(safeSaveName('测试.pdf'), '测试.pdf');
  });
}
