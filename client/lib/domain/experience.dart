import 'case_fields.dart';

/// 仅用于离线交互体验，不能作为真实案件或上传凭证。
class ExperienceTask {
  const ExperienceTask({
    required this.id,
    required this.title,
    this.done = false,
  });
  final String id;
  final String title;
  final bool done;
}

class ExperienceFile {
  const ExperienceFile({
    required this.id,
    required this.version,
    this.category = 'EVIDENCE',
  });
  final String id;
  final int version;
  final String category;
  String get name => '虚构示例材料.pdf';
}

class ExperienceCase {
  ExperienceCase({
    required this.id,
    required this.caseNo,
    required this.cause,
    required this.court,
    this.stage = 'FIRST_INSTANCE',
    this.status = 'ACTIVE',
    List<ExperienceTask> tasks = const [],
    List<ExperienceFile> files = const [],
  }) : tasks = List.unmodifiable(tasks),
       files = List.unmodifiable(files);

  final String id;
  final String caseNo;
  final String cause;
  final String court;
  final String stage;
  final String status;
  CaseFields get fields => CaseFields(
    caseNo: caseNo,
    cause: cause,
    court: court,
    stage: stage,
    status: status,
  );
  final List<ExperienceTask> tasks;
  final List<ExperienceFile> files;

  ExperienceCase copyWith({
    CaseFields? fields,
    List<ExperienceTask>? tasks,
    List<ExperienceFile>? files,
  }) => ExperienceCase(
    id: id,
    caseNo: fields?.caseNo ?? caseNo,
    cause: fields?.cause ?? cause,
    court: fields?.court ?? court,
    stage: fields?.stage ?? stage,
    status: fields?.status ?? status,
    tasks: tasks ?? this.tasks,
    files: files ?? this.files,
  );
}

/// 离线体验专用边界；真实 API 仓库将在独立交付中接入，避免把演示误报为联调。
abstract class ExperienceRepository {
  Future<List<ExperienceCase>> load();
  Future<String> create(String caseNo, String cause, String court);
  Future<void> update(String caseId, CaseFields fields);
  Future<void> remove(String caseId);
  Future<void> addTask(String caseId, String title);
  Future<void> toggleTask(String caseId, String taskId);
  Future<void> addSample(String caseId, {String category = 'EVIDENCE'});
  Future<void> removeFile(String caseId, String fileId);
}

class ExperienceFailure implements Exception {
  const ExperienceFailure(this.message);
  final String message;
}
