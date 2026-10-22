import 'package:dio/dio.dart';
import 'api_fixture.dart';
import 'online_fixture.dart';

/// 界面专用分页/日期排序协议替身；真实权限和数据库由 Dart 联调独立检查。
class TaskEditFixture extends OnlineFixture {
  bool failReadAfterWrite = false;
  bool _failNextRead = false;
  @override
  ResponseBody handle(RequestOptions request) {
    if (request.method == 'GET' &&
        request.path.endsWith('/tasks') &&
        !expire &&
        !failRead) {
      requests.add('${request.method} ${request.path}');
      if (_failNextRead) {
        _failNextRead = false;
        return reply(null, 503);
      }
      final page = int.parse(request.queryParameters['page'].toString());
      final indexed = work.asMap().entries.toList()
        ..sort((a, b) {
          final first = a.value['dueDate'] as String? ?? '9999-99-99';
          final second = b.value['dueDate'] as String? ?? '9999-99-99';
          final date = first.compareTo(second);
          return date == 0 ? a.key.compareTo(b.key) : date;
        });
      return reply({
        'items': indexed
            .skip((page - 1) * 20)
            .take(20)
            .map((e) => e.value)
            .toList(),
        'total': work.length,
        'page': page,
        'pageSize': 20,
      });
    }
    final result = super.handle(request);
    if (failReadAfterWrite && request.method == 'PATCH') _failNextRead = true;
    return result;
  }

  void seedTasks([int count = 1]) {
    seed();
    for (var i = 0; i < count; i++) {
      work.add({
        'id': 'task-$i',
        'title': '虚构任务$i',
        'description': '虚构原描述',
        'dueDate': '2028-03-01',
        'status': 'DONE',
        'source': 'MANUAL',
      });
    }
  }
}
