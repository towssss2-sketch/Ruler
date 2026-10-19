import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'package:ruler_client/infrastructure/case_conflict_wire.dart';
import 'api_fixture.dart';

Map<String, Object?> conflictRow([int index = 1]) => {
  'caseId': 'case-$index',
  'caseNo': '(2026)虚构民初${index + 100}号',
  'court': '虚构历史法院',
  'deleted': index == 1,
  'similarity': 0.625,
};
Map<String, Object?> conflictPage({
  int page = 1,
  int total = 1,
  List<Object?>? items,
}) => {
  'page': page,
  'pageSize': 20,
  'threshold': 0.6,
  'total': total,
  'items': items ?? [conflictRow()],
};
void main() {
  parseContract();
  apiContract();
}

void parseContract() {
  test('解析候选、历史删除状态与空的越界页，名单不可变', () {
    final result = readConflictPage(conflictPage(), expectedPage: 1);
    expect(result.items.single.deleted, isTrue);
    expect(result.items.single.similarity, 0.625);
    expect(() => result.items.clear(), throwsUnsupportedError);
    final empty = readConflictPage(
      conflictPage(page: 2, items: []),
      expectedPage: 2,
    );
    expect(empty.total, 1);
    expect(empty.items, isEmpty);
    expect(empty.hasNext, isFalse);
  });
  test('错误分页、阈值、重复候选和非有限分数不冒充正常检查结果', () {
    for (final patch in <Map<String, Object?>>[
      {'page': 0},
      {'page': 2},
      {'pageSize': 10},
      {'threshold': 0.5},
      {'total': -1},
      {'items': null},
      {'items': List.generate(21, conflictRow), 'total': 21},
      {
        'items': [conflictRow(), conflictRow()],
        'total': 2,
      },
      for (final score in [double.nan, double.infinity, -1, 1.1, 0.59, '0.6'])
        {
          'items': [
            {...conflictRow(), 'similarity': score},
          ],
        },
      {
        'items': [
          {...conflictRow(), 'deleted': 'true'},
        ],
      },
      {
        'items': [
          {...conflictRow(), 'caseNo': null},
        ],
      },
    ]) {
      expect(
        () => readConflictPage({...conflictPage(), ...patch}, expectedPage: 1),
        throwsA(isA<ApiFailure>()),
      );
    }
  });
}

void apiContract() {
  test('检查使用已保存案号路径与服务端分页，不发送阈值、姓名或用户参数', () async {
    RequestOptions? sent;
    final session = ApiSession(
      'https://example.invalid',
      dio: Dio()
        ..httpClientAdapter = TestAdapter((request) {
          if (request.path == '/auth/login') return reply(tokens());
          sent = request;
          return reply(conflictPage(page: 2, total: 21));
        }),
    );
    addTearDown(session.close);
    await session.login('fictional@example.invalid', 'fictional-password');
    final result = await ApiRepository(session).conflicts('one/two', page: 2);
    expect(result.page, 2);
    expect(sent!.path, '/cases/one%2Ftwo/conflict-check');
    expect(sent!.method, 'POST');
    expect(sent!.data, isNull);
    expect(sent!.queryParameters, {'page': 2, 'pageSize': 20});
  });
}
