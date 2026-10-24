import 'online.dart';

const ingestionStatuses = {
  'PENDING_MATCH': '待定',
  'MATCHED': '已匹配',
  'ASSIGNED': '已指派',
  'IGNORED': '已忽略',
};
const ingestionChannels = {'WECHAT': '微信转发', 'SMS': '短信', 'EMAIL': '邮箱'};

/// 与服务端一致的轻量文字处理；不提取链接、不猜测材料分类或法律日期。
String normalizeIngestionText(String text) =>
    text.trim().replaceAll(RegExp(r'\r\n?'), '\n');
String? ingestionTextError(String text) {
  final value = normalizeIngestionText(text);
  if (value.isEmpty) return '请填写虚构转发文字。';
  if (value.runes.length > 10000 || value.contains('\u0000')) {
    return '文字最多 10000 字，且不能包含零字节。';
  }
  return null;
}

class IngestionItem {
  const IngestionItem({
    required this.id,
    required this.channel,
    required this.status,
    required this.preview,
    required this.receivedAt,
    this.rawContent,
    this.file,
  });
  final String id, channel, status, preview;
  final DateTime receivedAt;
  final String? rawContent;
  final IngestionFile? file;
}

class IngestionReceipt {
  const IngestionReceipt(this.id, this.status, this.duplicate);
  final String id, status;
  final bool duplicate;
  String get message =>
      duplicate ? '这段文字已接收，未重复创建；当前${ingestionStatuses[status]}。' : '已保存到待定区。';
}

abstract interface class IngestionRepository {
  Future<IngestionReceipt> receive(String text);
  Future<OnlinePage<IngestionItem>> list({int page = 1, bool history = false});
  Future<IngestionItem> detail(String id);
  Future<void> ignore(String id);
}

/// 待定区附件信息，无案件/分类，不持有内部对象键或访问签名。
class IngestionFile {
  const IngestionFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
  });
  final String id, name, mimeType;
  final int size;
}
