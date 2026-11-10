import 'dart:async';
import 'package:dio/dio.dart';
import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/domain/saved_classification.dart';
import 'preview_attempt_fixture.dart';
import 'ingestion_fixture.dart';
import 'api_fixture.dart';

const savedAttemptId = '00000000-0000-4000-8000-000000000001';
Map<String, Object?> savedRow({String state = 'RECORDED'}) => {
  'attemptId': savedAttemptId,
  'state': state,
  'classification': state != 'RECORDED'
      ? null
      : <String, Object?>{
          'category': 'SERVICE_CONTRACT',
          'ruleVersion': 'title-v1',
          'reason': 'TITLE_MATCH',
          'requiresConfirmation': true,
        },
};

class ClassificationFixture extends AttemptFixture
    implements SavedClassifications {
  ClassificationFixture() {
    status = 'SUCCEEDED';
  }
  String savedState = 'RECORDED', savedReason = 'TITLE_MATCH';
  String? savedCategory = 'SERVICE_CONTRACT';
  bool failClassification = false;
  final reads = <(String, String)>[];
  Completer<SavedClassification>? classificationGate;
  @override
  Future<SavedClassification> classification(
    String id,
    String attemptId,
  ) async {
    reads.add((id, attemptId));
    if (classificationGate != null) return classificationGate!.future;
    if (failClassification) throw const ApiFailure('分类暂时无法读取，请重试。');
    return SavedClassification(
      attemptId: attemptId,
      state: savedState,
      category: savedState == 'RECORDED' ? savedCategory : null,
      reason: savedState == 'RECORDED' ? savedReason : null,
      ruleVersion: savedState == 'RECORDED' ? 'title-v1' : null,
    );
  }
}

class ClassificationSessionFixture extends IngestionFixture {
  @override
  ResponseBody handle(RequestOptions r) {
    if (!expire && r.path.endsWith('/preview-attempts')) {
      requests.add('${r.method} ${r.path}');
      return reply(attemptPage());
    }
    if (!expire && r.path.endsWith('/classification')) {
      requests.add('${r.method} ${r.path}');
      return reply(savedRow());
    }
    return super.handle(r);
  }
}
