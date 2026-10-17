import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'api_fixture.dart';

void main() {
  for (final invalid in ['2026', '2026-02-30', 'private-invalid-value']) {
    test('任务日期格式异常时拒绝响应：$invalid', () async {
      final session = ApiSession(
        'https://example.invalid',
        dio: Dio()
          ..httpClientAdapter = TestAdapter((request) {
            if (request.path == '/auth/login') return reply(tokens());
            return reply({
              'items': [
                {
                  'id': 'task-1',
                  'title': '虚构任务',
                  'status': 'TODO',
                  'dueDate': invalid,
                },
              ],
              'total': 1,
              'page': 1,
            });
          }),
      );
      addTearDown(session.close);
      await session.login('test@example.invalid', 'fictional-password');
      await expectLater(
        ApiRepository(session).tasks('case-1'),
        throwsA(
          isA<ApiFailure>().having((e) => e.message, 'safe', '服务响应格式异常。'),
        ),
      );
    });
  }
}
