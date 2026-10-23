import '../domain/ingestion.dart';
import '../domain/online.dart';
import 'api_session.dart';
import 'ingestion_wire.dart';

/// 独立用例共用当前登录会话，不创建额外凭据或本地原文缓存。
class ApiIngestion implements IngestionRepository {
  ApiIngestion(this.session);
  final ApiSession session;
  @override
  Future<IngestionReceipt> receive(String text) async {
    final error = ingestionTextError(text);
    if (error != null) throw ApiFailure(error);
    return readIngestionReceipt(
      await session.request(
        'POST',
        '/ingestion/wechat',
        data: {'rawContent': normalizeIngestionText(text)},
      ),
    );
  }

  @override
  Future<OnlinePage<IngestionItem>> list({
    int page = 1,
    bool history = false,
  }) async => readIngestionPage(
    await session.request(
      'GET',
      history ? '/ingestion/logs' : '/ingestion/pending',
      query: {'page': page, 'pageSize': 20},
    ),
    page,
    history,
  );

  @override
  Future<IngestionItem> detail(String id) async => readIngestionItem(
    await session.request('GET', '/ingestion/${Uri.encodeComponent(id)}'),
    detail: true,
  );

  @override
  Future<void> ignore(String id) async {
    final value = jsonObject(
      await session.request(
        'POST',
        '/ingestion/${Uri.encodeComponent(id)}/ignore',
        data: {},
      ),
    );
    if (value['ignored'] != true) throw const ApiFailure('忽略结果未确认，请刷新核对。');
  }
}
