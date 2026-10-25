import '../domain/ingestion_assignment.dart';
import '../domain/online.dart';
import '../domain/documents.dart';
import 'api_session.dart';
import 'document_wire.dart';

class ApiIngestionAssignment implements IngestionAssignment {
  ApiIngestionAssignment(this.session, this.repository);
  final ApiSession session;
  final OnlineRepository repository;
  @override
  Future<OnlinePage<OnlineCase>> cases({String keyword = '', int page = 1}) =>
      repository.cases(keyword: keyword, page: page);

  @override
  Future<AssignmentReceipt> assign(
    String id,
    String caseId,
    String category,
  ) async {
    if (!documentCategories.containsKey(category)) {
      throw const ApiFailure('请选择有效分类。');
    }
    final result = jsonObject(
      await session.request(
        'POST',
        '/ingestion/${Uri.encodeComponent(id)}/assign',
        data: {'caseId': caseId, 'category': category},
      ),
    );
    final document = parseDocument(result);
    if (result['caseId'] != caseId ||
        result['ingestionId'] != id ||
        !['WECHAT', 'SMS', 'EMAIL'].contains(result['source']) ||
        document.category != category) {
      throw const ApiFailure('归档结果未确认，请保留选择重试或刷新核对。');
    }
    return AssignmentReceipt(document.id, caseId, category);
  }
}
