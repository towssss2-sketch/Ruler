import '../domain/online.dart';
import '../domain/task_fields.dart';
import 'api_session.dart';

/// 手动任务列表严格校验来源和资料，拒绝把其他来源任务交给普通编辑器。
OnlineTask readManualTask(Map<String, Object?> value) {
  final status = value['status'];
  final rawDate = value['dueDate'];
  final description = value['description'];
  if (value['source'] != 'MANUAL' ||
      !['TODO', 'DONE'].contains(status) ||
      (description != null && description is! String)) {
    throw const ApiFailure('服务响应格式异常。');
  }
  final fields = TaskFields(
    title: jsonText(value, 'title'),
    description: description as String?,
    dueDate: _workDate(rawDate),
  );
  if (fields.error != null) throw const ApiFailure('服务响应格式异常。');
  return OnlineTask(
    jsonText(value, 'id'),
    fields.title,
    status == 'DONE',
    fields.dueDate,
    description: fields.description,
  );
}

String? _workDate(Object? raw) {
  if (raw == null) return null;
  if (raw is! String ||
      !RegExp(r'^[1-9]\d{3}-\d{2}-\d{2}(T00:00:00\.000Z)?$').hasMatch(raw) ||
      !validWorkDate(raw.substring(0, 10))) {
    throw const ApiFailure('服务响应格式异常。');
  }
  return raw.substring(0, 10);
}
