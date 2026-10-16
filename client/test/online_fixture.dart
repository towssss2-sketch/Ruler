import 'package:dio/dio.dart';
import 'api_fixture.dart';

/// 界面测试的协议替身；真实 HTTP/数据库另由 connected_e2e 验证。
class OnlineFixture {
  bool denyLogin = false;
  bool expire = false;
  bool failWrite = false;
  bool failRead = false;
  final records = <Map<String, Object?>>[];
  final work = <Map<String, Object?>>[];
  final requests = <String>[];

  Dio dio() => Dio()..httpClientAdapter = TestAdapter(handle);

  ResponseBody handle(RequestOptions request) {
    requests.add('${request.method} ${request.path}');
    if (request.path == '/auth/login') {
      return denyLogin ? reply(null, 401) : reply(tokens());
    }
    if (expire) return reply(null, 401);
    if (request.path == '/auth/logout') return reply({'loggedOut': true});
    if (request.method == 'GET' && failRead) return reply(null, 503);
    if (request.method != 'GET' && failWrite) return reply(null, 409);
    final input = request.data as Map<String, Object?>? ?? {};
    if (request.path == '/cases') return _cases(request, input);
    if (request.path.endsWith('/tasks')) {
      if (request.method == 'POST') {
        work.add({
          'id': 'task-${work.length}',
          'title': input['title'],
          'status': 'TODO',
          'dueDate': input['dueDate'],
        });
        return reply(work.last, 201);
      }
      return _page(work);
    }
    if (request.path.startsWith('/tasks/')) {
      final id = request.path.split('/').last;
      if (request.method == 'DELETE') {
        work.removeWhere((item) => item['id'] == id);
        return reply({'deleted': true});
      }
      final item = work.singleWhere((item) => item['id'] == id);
      item['status'] = input['status'];
      return reply(item);
    }
    if (request.method == 'DELETE') {
      records.removeWhere((item) => item['id'] == request.path.split('/').last);
      return reply({'deleted': true});
    }
    return reply(null, 404);
  }

  ResponseBody _cases(RequestOptions request, Map<String, Object?> input) {
    if (request.method == 'POST') {
      final item = {'id': 'case-${records.length}', ...input};
      records.add(item);
      return reply(item, 201);
    }
    final keyword = request.queryParameters['keyword'] as String? ?? '';
    return _page(
      records
          .where((item) => (item['caseNo'] as String).contains(keyword))
          .toList(),
    );
  }

  ResponseBody _page(List<Map<String, Object?>> items) =>
      reply({'items': items, 'total': items.length, 'page': 1, 'pageSize': 20});

  void seed() => records.add({
    'id': 'case-1',
    'caseNo': '(2026)虚构民初1号',
    'cause': '虚构合同纠纷',
    'court': '虚构测试法院',
  });
}
