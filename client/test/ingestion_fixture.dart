import 'dart:async';
import 'package:dio/dio.dart';
import 'api_fixture.dart';
import 'online_fixture.dart';

Map<String, Object?> ingestionRow([int i = 0]) => {
  'id': 'inbox-$i',
  'channel': 'WECHAT',
  'status': 'PENDING_MATCH',
  'preview': '虚构转发文字$i',
  'rawContent': '虚构转发文字$i',
  'receivedAt': '2026-10-23T02:00:00.000Z',
};
Map<String, Object?> ingestionPage(
  List<Map<String, Object?>> items, {
  int page = 1,
  int? total,
}) => {
  'items': items,
  'page': page,
  'pageSize': 20,
  'total': total ?? items.length,
};

/// 仅 Widget 协议夹具；真实后端独立通过 Dart 联调验证。
class IngestionFixture extends OnlineFixture {
  final entries = <Map<String, Object?>>[];
  bool failAfterWrite = false, loseReceiveReply = false;
  Completer<void>? writeGate;
  @override
  Dio dio() => Dio()
    ..httpClientAdapter = TestAdapter((r) async {
      if (r.method == 'POST' && r.path.startsWith('/ingestion')) {
        await writeGate?.future;
      }
      return handle(r);
    });

  @override
  ResponseBody handle(RequestOptions r) {
    if (!r.path.startsWith('/ingestion')) return super.handle(r);
    requests.add('${r.method} ${r.path}');
    if (expire) return reply(null, 401);
    if (r.method == 'GET' && failRead) return reply(null, 503);
    if (r.method == 'POST' && failWrite) return reply(null, 409);
    if (r.path == '/ingestion/wechat') return _receive(r);
    if (r.path.endsWith('/ignore')) {
      entries.singleWhere((e) => e['id'] == r.path.split('/')[2])['status'] =
          'IGNORED';
      if (failAfterWrite) failRead = true;
      return reply({'ignored': true});
    }
    if (r.path == '/ingestion/pending' || r.path == '/ingestion/logs') {
      final items = entries
          .where(
            (e) => r.path.endsWith('/logs') || e['status'] == 'PENDING_MATCH',
          )
          .toList();
      final page = r.queryParameters['page'] as int;
      return reply(
        ingestionPage(
          items.skip((page - 1) * 20).take(20).toList(),
          page: page,
          total: items.length,
        ),
      );
    }
    return reply(entries.singleWhere((e) => e['id'] == r.path.split('/').last));
  }

  ResponseBody _receive(RequestOptions r) {
    final text = (r.data as Map)['rawContent'] as String;
    final existing = entries.where((e) => e['rawContent'] == text);
    final duplicate = existing.isNotEmpty;
    if (!duplicate) {
      entries.insert(0, {
        ...ingestionRow(entries.length),
        'preview': String.fromCharCodes(text.runes.take(200)),
        'rawContent': text,
      });
    }
    final item = duplicate ? existing.first : entries.first;
    if (loseReceiveReply) {
      loseReceiveReply = false;
      return reply(null, 503);
    }
    if (failAfterWrite) failRead = true;
    return reply({
      'id': item['id'],
      'status': item['status'],
      'duplicate': duplicate,
    }, 201);
  }
}
