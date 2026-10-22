import 'package:ruler_client/domain/online.dart';
import 'package:ruler_client/domain/task_fields.dart';
import 'package:ruler_client/infrastructure/api_repository.dart';
import 'connected_e2e.dart' show check, forbidden;

const editedTask = TaskFields(
  title: '虚构已修改任务',
  description: '虚构第一行\n虚构第二行',
  dueDate: '2028-02-29',
);
String? _persistedTaskId;

/// 复用已有完成任务，真实修改三项资料并由原列表读取断言状态保留。
Future<void> editCompletedTask(ApiRepository repository, String id) =>
    repository.updateTask(id, editedTask);

void verifyEditedTask(OnlineTask task) {
  check(task.done && task.title == editedTask.title);
  check(
    task.description == editedTask.description &&
        task.dueDate == editedTask.dueDate,
  );
}

/// 普通更新清空可选资料，完成状态由前一步独立恢复，不能被资料更新覆盖。
Future<void> clearTask(ApiRepository repository, String id) =>
    repository.updateTask(id, const TaskFields(title: '虚构已清空任务'));

void verifyClearedTask(OnlineTask task) {
  check(!task.done && task.title == '虚构已清空任务');
  check(task.description == null && task.dueDate == null);
}

/// 新会话实际读取已有任务，记录身份用于另一个账号的越权写入检查。
Future<void> verifyTaskPersistence(
  ApiRepository repository,
  String caseId,
) async {
  final task = (await repository.tasks(caseId)).items.single;
  check(task.title == '虚构持久化任务' && !task.done);
  check(task.description == '虚构持久化描述' && task.dueDate == '2028-02-29');
  _persistedTaskId = task.id;
}

Future<void> taskEditIsolation(ApiRepository repository) async {
  check(_persistedTaskId != null);
  await forbidden(() => repository.updateTask(_persistedTaskId!, editedTask));
}
