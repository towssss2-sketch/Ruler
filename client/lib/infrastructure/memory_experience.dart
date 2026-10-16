import '../domain/experience.dart';

/// 只保存本进程的虚构体验数据；无网络、磁盘和真实验证码。
class MemoryExperience implements ExperienceRepository {
  final Map<String, ExperienceCase> _cases = {};
  final Map<String, int> _versions = {};
  int _sequence = 0;

  @override
  Future<List<ExperienceCase>> load() async =>
      List.unmodifiable(_cases.values.toList().reversed);

  @override
  Future<String> create(String caseNo, String cause, String court) async {
    if ([caseNo, cause, court].any((value) => value.trim().isEmpty)) {
      throw const ExperienceFailure('请填写案号、案由和法院');
    }
    if (_cases.values.any(
      (item) => item.caseNo == caseNo.trim() && item.court == court.trim(),
    )) {
      throw const ExperienceFailure('体验案件的案号和法院重复');
    }
    final id = 'demo-${++_sequence}';
    _cases[id] = ExperienceCase(
      id: id,
      caseNo: caseNo.trim(),
      cause: cause.trim(),
      court: court.trim(),
    );
    return id;
  }

  ExperienceCase _record(String id) =>
      _cases[id] ?? (throw const ExperienceFailure('体验案件已移除'));

  @override
  Future<void> remove(String caseId) async {
    _record(caseId);
    _cases.remove(caseId);
  }

  @override
  Future<void> addTask(String caseId, String title) async {
    if (title.trim().isEmpty || title.trim().length > 255) {
      throw const ExperienceFailure('请填写 1–255 字的任务标题');
    }
    final record = _record(caseId);
    _cases[caseId] = record.copyWith(
      tasks: [
        ...record.tasks,
        ExperienceTask(id: 'demo-${++_sequence}', title: title.trim()),
      ],
    );
  }

  @override
  Future<void> toggleTask(String caseId, String taskId) async {
    final record = _record(caseId);
    if (!record.tasks.any((task) => task.id == taskId)) {
      throw const ExperienceFailure('体验任务不存在');
    }
    _cases[caseId] = record.copyWith(
      tasks: record.tasks
          .map(
            (task) => task.id == taskId
                ? ExperienceTask(
                    id: task.id,
                    title: task.title,
                    done: !task.done,
                  )
                : task,
          )
          .toList(),
    );
  }

  @override
  Future<void> addSample(String caseId) async {
    final record = _record(caseId);
    final version = (_versions[caseId] ?? 0) + 1;
    _versions[caseId] = version;
    _cases[caseId] = record.copyWith(
      files: [
        ...record.files,
        ExperienceFile(id: 'demo-${++_sequence}', version: version),
      ],
    );
  }

  @override
  Future<void> removeFile(String caseId, String fileId) async {
    final record = _record(caseId);
    _cases[caseId] = record.copyWith(
      files: record.files.where((file) => file.id != fileId).toList(),
    );
  }
}
