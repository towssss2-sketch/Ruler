import '../domain/ingestion.dart';
import '../domain/ingestion_files.dart';
import '../domain/online.dart';
import 'api_session.dart';
import 'document_wire.dart';
import 'ingestion_wire.dart';

/// 精确解析文件尺寸和格式，坏附件不能静默降级为文字条目。
IngestionFile readIngestionFile(Object? raw) {
  final row = jsonObject(raw);
  final value = row['sizeBytes'];
  final size = value is String && RegExp(r'^[1-9][0-9]*$').hasMatch(value)
      ? int.tryParse(value)
      : null;
  if (size == null) throw const ApiFailure('附件资料异常，请刷新重试。');
  final name = jsonText(row, 'fileName');
  final mime = jsonText(row, 'mimeType');
  validateFileMetadata(name, mime, size);
  return IngestionFile(
    id: jsonText(row, 'id'),
    name: name,
    mimeType: mime,
    size: size,
  );
}

IngestionFileReceipt readFileReceipt(Object? raw) {
  final row = jsonObject(raw);
  final receipt = readIngestionReceipt(row);
  return IngestionFileReceipt(
    receipt.id,
    receipt.status,
    receipt.duplicate,
    readIngestionFile(row['file']),
  );
}
