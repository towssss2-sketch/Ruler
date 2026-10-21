import 'package:dio/dio.dart';
import 'api_fixture.dart';
import 'online_fixture.dart';

/// 独立协议替身，只验证客户端查询行为；真实 SQL 另由 Dart 联调覆盖。
class FilterFixture extends OnlineFixture {
  final queries = <Map<String, Object?>>[];
  @override
  ResponseBody handle(RequestOptions request) {
    if (request.path == '/cases' && request.method == 'GET') {
      queries.add(Map.of(request.queryParameters));
      if (!expire && !failRead) return filtered(request.queryParameters);
    }
    return super.handle(request);
  }

  ResponseBody filtered(Map<String, Object?> query) {
    final keyword = query['keyword'] as String? ?? '';
    final items = records
        .where(
          (record) =>
              ['court', 'stage', 'status'].every(
                (key) => query[key] == null || record[key] == query[key],
              ) &&
              ((record['caseNo'] as String).contains(keyword) ||
                  (record['cause'] as String).contains(keyword)),
        )
        .toList();
    items.sort((a, b) {
      final updated = (a['updatedOrder'] as int).compareTo(
        b['updatedOrder'] as int,
      );
      final order = updated == 0
          ? (a['id'] as String).compareTo(b['id'] as String)
          : updated;
      return query['sort'] == 'asc' ? order : -order;
    });
    final page = query['page'] as int;
    return reply({
      'items': items.skip((page - 1) * 20).take(20).toList(),
      'total': items.length,
      'page': page,
      'pageSize': 20,
    });
  }

  void add(
    int index, {
    String court = '虚构法院甲',
    String stage = 'FIRST_INSTANCE',
    String status = 'ACTIVE',
  }) {
    records.add({
      'id': 'case-$index',
      'caseNo': '(2026)虚构民初$index号',
      'cause': '虚构案由$index',
      'court': court,
      'stage': stage,
      'status': status,
      'updatedOrder': index,
    });
  }
}
