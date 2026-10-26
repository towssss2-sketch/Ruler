import 'dart:async';
import 'package:dio/dio.dart';
import 'package:ruler_client/domain/ingestion_preview.dart';
import 'package:ruler_client/domain/ingestion.dart';
import 'package:ruler_client/domain/online.dart';
import 'api_fixture.dart';
import 'ingestion_assign_fixture.dart';
import 'ingestion_fixture.dart';

Map<String, Object?> previewRow() => {
  'attemptId': '00000000-0000-4000-8000-000000000001',
  'extraction': {'state': 'TEXT', 'text': '法律服务合同\n仅为虚构联调正文。'},
  'suggestion': {
    'ruleVersion': 'title-v1',
    'category': 'SERVICE_CONTRACT',
    'reason': 'TITLE_MATCH',
    'caseNumbers': ['(2026)虚构民初90号'],
    'caseNumbersTruncated': false,
    'requiresConfirmation': true,
  },
};

IngestionPreviewResult previewResult({
  String? category = 'SERVICE_CONTRACT',
  String reason = 'TITLE_MATCH',
  bool truncated = false,
  String? text,
}) => IngestionPreviewResult(
  attemptId: 'fixture-attempt',
  text: text ?? '法律服务合同\n仅为虚构联调正文。',
  suggestion: PreviewSuggestion(
    category: category,
    reason: reason,
    truncated: truncated,
    caseNumbers: truncated
        ? List.generate(10, (i) => '(2026)虚构民初${i + 1}号')
        : ['(2026)虚构民初90号'],
  ),
);

/// 协议与界面替身；实际 PDF 解析由真实 Dart/MinIO 联调另行证明。
class PreviewFixture implements IngestionPreview {
  final assigned = AssignmentFixture();
  late final inbox = PreviewInbox(assigned.inbox);
  IngestionPreviewResult result = previewResult();
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<IngestionPreviewResult> preview(String id) async {
    calls++;
    await gate?.future;
    if (fail) throw const ApiFailure('正文提取暂不可用，请稍后重试。');
    return result;
  }
}

class PreviewInbox implements IngestionRepository {
  PreviewInbox(this.inner);
  final IngestionRepository inner;
  bool failDetail = false;
  @override
  Future<IngestionItem> detail(String id) async {
    if (failDetail) throw const ApiFailure('材料状态核对失败，请重试。');
    return inner.detail(id);
  }

  @override
  Future<IngestionReceipt> receive(String text) => inner.receive(text);
  @override
  Future<OnlinePage<IngestionItem>> list({
    int page = 1,
    bool history = false,
  }) => inner.list(page: page, history: history);
  @override
  Future<void> ignore(String id) => inner.ignore(id);
}

class PreviewSessionFixture extends IngestionFixture {
  int previewCalls = 0;
  @override
  ResponseBody handle(RequestOptions r) {
    if (!expire && r.path.endsWith('/preview')) {
      requests.add('${r.method} ${r.path}');
      previewCalls++;
      return reply(previewRow(), 201);
    }
    return super.handle(r);
  }
}
