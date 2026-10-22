import 'dart:async';
import 'package:dio/dio.dart';
import 'api_fixture.dart';
import 'online_fixture.dart';

Map<String, Object?> todayTask([int index = 0]) => {
  'id': 'today-$index',
  'caseId': 'case-1',
  'caseNo': '(2026)虚构民初1号',
  'court': '虚构测试法院',
  'title': '虚构今日任务$index',
  'description': '虚构任务说明',
  'source': 'MANUAL',
  'status': 'TODO',
  'dueDate': '2026-10-22T00:00:00.000Z',
};
Map<String, Object?> confirmedTask() => {
  ...todayTask(),
  'id': 'deadline',
  'title': '虚构已确认期间',
  'source': 'DEADLINE_RULE',
  'dueDate': '2026-10-25T00:00:00.000Z',
  'baseDate': '2026-10-20T00:00:00.000Z',
  'deadlineType': 'OTHER',
  'deadlineConfirmedAt': '2026-10-21T03:00:00.000Z',
  'deadlineConfirmedById': 'fictional-owner',
};
Map<String, Object?> todayPage(
  List<Map<String, Object?>> items, {
  int page = 1,
  int? total,
}) => {
  'date': '2026-10-22',
  'timeZone': 'Asia/Shanghai',
  'items': items,
  'total': total ?? items.length,
  'page': page,
  'pageSize': 20,
};

/// 仅模拟页面协议；排序/权限的真实数据库行为另经联调和后端 e2e 验证。
class TodayFixture extends OnlineFixture {
  bool failAfterWrite = false;
  Completer<void>? writeGate;
  @override
  Dio dio() => Dio()
    ..httpClientAdapter = TestAdapter((request) async {
      if (request.method == 'PATCH' && writeGate != null) {
        await writeGate!.future;
      }
      return handle(request);
    });
  @override
  ResponseBody handle(RequestOptions request) {
    if (request.path == '/tasks/today' && !expire && !failRead) {
      requests.add('${request.method} ${request.path}');
      final page = request.queryParameters['page'] as int;
      final pending = work.where((t) => t['status'] == 'TODO').toList();
      return reply(
        todayPage(
          pending.skip((page - 1) * 20).take(20).toList(),
          page: page,
          total: pending.length,
        ),
      );
    }
    if (request.method == 'GET' &&
        request.path.endsWith('/tasks') &&
        !expire &&
        !failRead) {
      requests.add('${request.method} ${request.path}');
      final items = work.where((t) => t['source'] == 'MANUAL').toList();
      return reply({
        'items': items,
        'total': items.length,
        'page': 1,
        'pageSize': 20,
      });
    }
    final response = super.handle(request);
    if (request.method == 'PATCH' && failAfterWrite && !failWrite) {
      failRead = true;
    }
    return response;
  }

  void seedToday([int count = 1]) {
    seed();
    work.addAll(List.generate(count, todayTask));
  }
}
