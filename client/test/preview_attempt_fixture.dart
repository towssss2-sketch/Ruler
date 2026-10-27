import 'dart:async';
import 'package:dio/dio.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/domain/preview_attempts.dart';
import 'package:ruler_client/infrastructure/api_ingestion_preview.dart';
import 'package:ruler_client/infrastructure/api_session.dart';
import 'api_fixture.dart';
import 'ingestion_preview_fixture.dart';

Map<String, Object?> attemptRow({
  String status = 'SUCCEEDED',
  String? reason,
  int index = 1,
}) => {
  'id': '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  'status': status,
  'reason': reason,
  'startedAt': '2026-10-27T00:00:00.000Z',
  'finishedAt': status == 'RUNNING' ? null : '2026-10-27T00:02:00.000Z',
  'retryable':
      status == 'INTERRUPTED' ||
      (status == 'MANUAL_REQUIRED' &&
          ['TIMEOUT', 'UNAVAILABLE'].contains(reason)),
};
Map<String, Object?> attemptPage([List<Object?>? rows]) => {
  'items': rows ?? [attemptRow()],
  'total': rows?.length ?? 1,
  'page': 1,
  'pageSize': 20,
};

class AttemptProtocol {
  Object? response = attemptPage();
  int status = 200;
  final requests = <RequestOptions>[];
  Completer<void>? gate;
  late final session = ApiSession(
    'http://127.0.0.1:3000',
    dio: Dio()
      ..httpClientAdapter = TestAdapter((r) async {
        requests.add(r);
        if (r.path == '/auth/login') return reply(tokens());
        await gate?.future;
        return reply(response, status);
      }),
  );
  late final api = ApiIngestionPreview(session);
  Future<void> login() =>
      session.login('fictional@example.invalid', 'fictional-password');
}

class AttemptFixture extends PreviewFixture implements PreviewAttempts {
  final pages = <int>[];
  String status = 'INTERRUPTED';
  String? reason;
  bool failRead = false;
  int total = 1;
  Completer<OnlinePage<PreviewAttempt>>? pending;
  @override
  Future<OnlinePage<PreviewAttempt>> attempts(String id, {int page = 1}) async {
    pages.add(page);
    if (pending != null) return pending!.future;
    if (failRead) throw const ApiFailure('记录暂不可用，请重试。');
    final rows = List.generate(
      total,
      (i) => PreviewAttempt(
        id: 'fixture-$i',
        status: status,
        reason: reason,
        startedAt: DateTime.utc(2026, 10, 27),
        finishedAt: status == 'RUNNING'
            ? null
            : DateTime.utc(2026, 10, 27, 0, 2),
        retryable:
            status == 'INTERRUPTED' ||
            ['TIMEOUT', 'UNAVAILABLE'].contains(reason),
      ),
    );
    return OnlinePage(
      rows.skip((page - 1) * 20).take(20).toList(),
      total,
      page,
    );
  }
}
