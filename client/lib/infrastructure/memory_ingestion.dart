import '../domain/ingestion.dart';
import '../domain/ingestion_files.dart';
import '../domain/online.dart';

/// 仅内存虚构体验，与在线会话和真实材料仓库分离，重启后清除。
class MemoryIngestion implements IngestionRepository {
  final _items = <IngestionItem>[];
  int _sequence = 0;
  @override
  Future<IngestionReceipt> receive(String text) async {
    final error = ingestionTextError(text);
    if (error != null) throw ApiFailure(error);
    final normalized = normalizeIngestionText(text);
    for (final item in _items) {
      if (item.file == null && item.rawContent == normalized) {
        return IngestionReceipt(item.id, item.status, true);
      }
    }
    final item = IngestionItem(
      id: 'demo-ingestion-${++_sequence}',
      channel: 'WECHAT',
      status: 'PENDING_MATCH',
      preview: String.fromCharCodes(normalized.runes.take(200)),
      rawContent: normalized,
      receivedAt: DateTime.now().toUtc(),
    );
    _items.insert(0, item);
    return IngestionReceipt(item.id, item.status, false);
  }

  /// 仅生成一条虚构附件元数据，不读取设备或伪造已上传原件。
  Future<IngestionReceipt> addFileExample() async {
    for (final item in _items) {
      if (item.file != null) {
        return IngestionFileReceipt(item.id, item.status, true, item.file!);
      }
    }
    final id = 'demo-ingestion-${++_sequence}';
    final file = IngestionFile(
      id: '$id-file',
      name: '虚构服务合同示例.pdf',
      mimeType: 'application/pdf',
      size: 1024,
    );
    _items.insert(
      0,
      IngestionItem(
        id: id,
        channel: 'WECHAT',
        status: 'PENDING_MATCH',
        preview: '虚构文件示例：${file.name}',
        rawContent: '仅展示文件待定条目，没有真实原件。',
        receivedAt: DateTime.now().toUtc(),
        file: file,
      ),
    );
    return IngestionFileReceipt(id, 'PENDING_MATCH', false, file);
  }

  @override
  Future<OnlinePage<IngestionItem>> list({
    int page = 1,
    bool history = false,
  }) async {
    final items = _items
        .where((item) => history || item.status == 'PENDING_MATCH')
        .toList();
    return OnlinePage(
      items.skip((page - 1) * 20).take(20).toList(),
      items.length,
      page,
    );
  }

  @override
  Future<IngestionItem> detail(String id) async => _items.firstWhere(
    (item) => item.id == id,
    orElse: () => throw const ApiFailure('材料不存在，请刷新核对。'),
  );

  @override
  Future<void> ignore(String id) async {
    final item = await detail(id);
    _items[_items.indexOf(item)] = IngestionItem(
      id: item.id,
      channel: item.channel,
      status: 'IGNORED',
      preview: item.preview,
      receivedAt: item.receivedAt,
      rawContent: item.rawContent,
      file: item.file,
    );
  }
}
