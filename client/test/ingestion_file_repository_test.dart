import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/ingestion_file_wire.dart';
import 'package:ruler_client/infrastructure/ingestion_wire.dart';
import 'package:ruler_client/infrastructure/memory_ingestion.dart';
import 'document_transfer_test.dart' show sample;
import 'ingestion_fixture.dart';
import 'ingestion_file_api_fixture.dart';

void main() {
  protocol();
  registration();
  transferRetry();
  cancellation();
  download();
  memory();
}

void protocol() {
  test('附件格式/精确尺寸损坏整体拒绝，文字和旧响应仍兼容', () {
    expect(readIngestionItem(ingestionRow()).file, isNull);
    final row = {...ingestionRow(), 'file': attachment()};
    expect(readIngestionItem(row).file!.name, sample.name);
    for (final change in <Map<String, Object?>>[
      {'sizeBytes': 3},
      {'sizeBytes': '03'},
      {'sizeBytes': '3.0'},
      {'sizeBytes': '0'},
      {'sizeBytes': '209715201'},
      {'mimeType': 'text/html'},
      {'fileName': '../x.pdf'},
      {'id': ''},
    ]) {
      expect(
        () => readIngestionItem({
          ...row,
          'file': {...attachment(), ...change},
        }),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(
      () => readFileReceipt({...fileReceipt(), 'file': null}),
      throwsA(isA<ApiFailure>()),
    );
  });
}

void registration() {
  test('登记失败只重试原票据，不重传；请求无案件、分类或内容哈希', () async {
    final f = FileApiFixture()..failRegister = true;
    addTearDown(f.close);
    await f.login();
    final upload = f.files.begin(sample);
    await expectLater(upload.resume(), throwsA(isA<ApiFailure>()));
    expect(upload.bytesUploaded, true);
    final result = await upload.resume();
    expect(result.file.name, sample.name);
    expect(result.duplicate, false);
    expect(await upload.resume(), same(result));
    expect(f.puts, 1);
    final presign = f.requests.where((r) => r.path.endsWith('/presign')).single;
    expect(presign.data, {
      'fileName': sample.name,
      'mimeType': sample.mimeType,
      'sizeBytes': 3,
      'contentMd5': sample.md5,
    });
    final completes = f.requests
        .where((r) => r.path == '/ingestion/files')
        .toList();
    expect(completes.length, 2);
    expect(
      completes.every(
        (r) => (r.data as Map).length == 1 && r.data['uploadId'] == 'ticket-1',
      ),
      true,
    );
  });
}

void transferRetry() {
  test('传输失败复用原票据，坏登记响应不能显示成功', () async {
    final f = FileApiFixture()..failUpload = true;
    addTearDown(f.close);
    await f.login();
    final upload = f.files.begin(sample);
    await expectLater(upload.resume(), throwsA(isA<ApiFailure>()));
    expect(upload.bytesUploaded, false);
    f.badReceipt = true;
    await expectLater(upload.resume(), throwsA(isA<ApiFailure>()));
    expect(upload.bytesUploaded, true);
    f.badReceipt = false;
    await upload.resume();
    expect(f.puts, 2);
    expect(f.requests.where((r) => r.path.endsWith('/presign')).length, 1);
  });
}

void cancellation() {
  test('取消、并发调用和会话结束不能继续上传或复用完成结果', () async {
    final f = FileApiFixture();
    addTearDown(f.close);
    await f.login();
    final cancelled = f.files.begin(sample)..cancel();
    await expectLater(cancelled.resume(), throwsA(isA<ApiFailure>()));
    expect(f.puts, 0);
    f.registerGate = Completer<void>();
    final upload = f.files.begin(sample);
    final pending = upload.resume();
    await Future<void>.delayed(Duration.zero);
    await expectLater(upload.resume(), throwsA(isA<ApiFailure>()));
    f.registerGate!.complete();
    await pending;
    f.session.close();
    await expectLater(upload.resume(), throwsA(isA<ApiFailure>()));
  });
}

void download() {
  test('下载每次重新授权，路径编码，返回精确原字节', () async {
    final f = FileApiFixture();
    addTearDown(f.close);
    await f.login();
    final file = readIngestionFile(attachment());
    for (var i = 0; i < 2; i++) {
      await f.files.download('fictional/id', file, (stream) async {
        expect(await stream.expand((chunk) => chunk).toList(), [97, 98, 99]);
      });
    }
    expect(f.gets, 2);
    expect(
      f.requests
          .where((r) => r.path == '/ingestion/fictional%2Fid/file/download')
          .length,
      2,
    );
  });
}

void memory() {
  test('虚构文件示例独立于文字，忽略保留附件且重复不恢复，无真实字节', () async {
    final repo = MemoryIngestion();
    final first = await repo.addFileExample();
    await repo.receive('虚构文件示例：虚构服务合同示例.pdf');
    expect((await repo.list()).total, 2);
    expect((await repo.addFileExample()).id, first.id);
    await repo.ignore(first.id);
    final again = await repo.addFileExample();
    expect(again.status, 'IGNORED');
    expect((await repo.detail(first.id)).file!.name, '虚构服务合同示例.pdf');
    expect((await MemoryIngestion().list()).total, 0);
  });
}
