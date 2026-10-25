import 'case_detail.dart';
import 'case_fields.dart';
import 'task_fields.dart';

/// 仅用于离线交互体验，不能作为真实案件或上传凭证。
class ExperienceTask {
  const ExperienceTask({
    required this.id,
    required this.title,
    this.done = false,
    this.description,
    this.dueDate,
  });
  final String id;
  final String title;
  final bool done;
  final String? description, dueDate;
  TaskFields get fields =>
      TaskFields(title: title, description: description, dueDate: dueDate);
  ExperienceTask copyWith({TaskFields? fields, bool? done}) => ExperienceTask(
    id: id,
    title: fields?.title ?? title,
    done: done ?? this.done,
    description: fields == null ? description : fields.description,
    dueDate: fields == null ? dueDate : fields.dueDate,
  );
}

class ExperienceFile {
  const ExperienceFile({
    required this.id,
    required this.version,
    this.category = 'EVIDENCE',
    this.name = '虚构示例材料.pdf',
    this.versionGroupId,
  });
  final String id;
  final int version;
  final String category;
  final String name;
  final String? versionGroupId;
  String get group => versionGroupId ?? category;
}

class ExperienceCase {
  ExperienceCase({
    required this.id,
    required this.caseNo,
    required this.cause,
    required this.court,
    this.stage = 'FIRST_INSTANCE',
    this.status = 'ACTIVE',
    this.supplement = const CaseSupplement(),
    DateTime? updatedAt,
    List<CaseParty> parties = const [],
    List<ExperienceTask> tasks = const [],
    List<ExperienceFile> files = const [],
  }) : updatedAt =
           updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
       parties = List.unmodifiable(parties),
       tasks = List.unmodifiable(tasks),
       files = List.unmodifiable(files);

  final String id;
  final String caseNo;
  final String cause;
  final String court;
  final String stage;
  final String status;
  final DateTime updatedAt;
  final CaseSupplement supplement;
  CaseFields get fields => CaseFields(
    caseNo: caseNo,
    cause: cause,
    court: court,
    stage: stage,
    status: status,
  );
  final List<CaseParty> parties;
  final List<ExperienceTask> tasks;
  final List<ExperienceFile> files;

  ExperienceCase copyWith({
    CaseFields? fields,
    CaseSupplement? supplement,
    DateTime? updatedAt,
    List<CaseParty>? parties,
    List<ExperienceTask>? tasks,
    List<ExperienceFile>? files,
  }) => ExperienceCase(
    id: id,
    updatedAt: updatedAt ?? this.updatedAt,
    caseNo: fields?.caseNo ?? caseNo,
    cause: fields?.cause ?? cause,
    court: fields?.court ?? court,
    stage: fields?.stage ?? stage,
    status: fields?.status ?? status,
    supplement: supplement ?? this.supplement,
    parties: parties ?? this.parties,
    tasks: tasks ?? this.tasks,
    files: files ?? this.files,
  );
}

/// 离线体验专用边界；真实 API 仓库将在独立交付中接入，避免把演示误报为联调。
abstract class ExperienceRepository {
  Future<List<ExperienceCase>> load();
  Future<String> create(
    String caseNo,
    String cause,
    String court, {
    List<CaseParty>? parties,
  });
  Future<void> update(String caseId, CaseFields fields);
  Future<void> saveParties(String caseId, List<CaseParty> parties);
  Future<void> saveSupplement(String caseId, CaseSupplement value);
  Future<void> remove(String caseId);
  Future<void> addTask(String caseId, String title);
  Future<void> updateTask(String caseId, String taskId, TaskFields fields);
  Future<void> toggleTask(String caseId, String taskId);
  Future<void> completeTask(String caseId, String taskId);
  Future<void> addSample(String caseId, {String category = 'EVIDENCE'});
  Future<void> removeFile(String caseId, String fileId);
  void archiveSample(
    String caseId,
    String ingestionId,
    String name,
    String category, {
    bool retry = false,
  }) => throw const ExperienceFailure('此体验仓库暂不支持归档');
}

class ExperienceFailure implements Exception {
  const ExperienceFailure(this.message);
  final String message;
}
