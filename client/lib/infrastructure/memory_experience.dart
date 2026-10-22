import '../domain/case_detail.dart';
import '../domain/case_fields.dart';
import '../domain/experience.dart';
import '../domain/documents.dart';
import '../domain/task_fields.dart';

/// 只保存本进程的虚构体验数据；无网络、磁盘和真实验证码。
class MemoryExperience implements ExperienceRepository {
  MemoryExperience({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final Map<String, ExperienceCase> _cases = {};
  final Map<String, int> _versions = {};
  int _sequence = 0;

  @override
  Future<List<ExperienceCase>> load() async =>
      List.unmodifiable(_cases.values.toList().reversed);

  @override
  Future<String> create(
    String caseNo,
    String cause,
    String court, {
    List<CaseParty>? parties,
  }) async {
    if ([caseNo, cause, court].any((value) => value.trim().isEmpty)) {
      throw const ExperienceFailure('请填写案号、案由和法院');
    }
    if (_cases.values.any(
      (item) => item.caseNo == caseNo.trim() && item.court == court.trim(),
    )) {
      throw const ExperienceFailure('体验案件的案号和法院重复');
    }
    final error = parties == null ? null : validateNewParties(parties);
    if (error != null) throw ExperienceFailure(error);
    final id = 'demo-${++_sequence}';
    _cases[id] = ExperienceCase(
      id: id,
      updatedAt: _now().toUtc(),
      caseNo: caseNo.trim(),
      cause: cause.trim(),
      court: court.trim(),
      parties:
          parties
              ?.map((party) => party.identified('demo-party-${++_sequence}'))
              .toList() ??
          const [],
    );
    return id;
  }

  ExperienceCase _record(String id) =>
      _cases[id] ?? (throw const ExperienceFailure('体验案件已移除'));

  /// 校验并修改虚构基础信息，原文件、任务和其他案件保持原状。
  @override
  Future<void> update(String caseId, CaseFields fields) async {
    final record = _record(caseId);
    if (validateCaseNumber(fields.caseNo) != null ||
        [
          fields.cause,
          fields.court,
        ].any((value) => value.trim().isEmpty || value.trim().length > 128) ||
        !caseStages.containsKey(fields.stage) ||
        !caseStatuses.containsKey(fields.status)) {
      throw const ExperienceFailure('请核对案号、案由、法院、阶段和状态');
    }
    final normalized = CaseFields(
      caseNo: normalizeCaseNumber(fields.caseNo),
      cause: fields.cause.trim(),
      court: fields.court.trim(),
      stage: fields.stage,
      status: fields.status,
    );
    if (_cases.values.any(
      (item) =>
          item.id != caseId &&
          normalizeCaseNumber(item.caseNo) == normalized.caseNo &&
          item.court == normalized.court,
    )) {
      throw const ExperienceFailure('体验案件的案号和法院重复');
    }
    _cases[caseId] = record.copyWith(
      fields: normalized,
      updatedAt: _now().toUtc(),
    );
  }

  /// 演示按本案 id 保留、添加及移除当事人，拒绝外案 id，保持其他数据。
  @override
  Future<void> saveParties(String caseId, List<CaseParty> parties) async {
    final current = _record(caseId);
    final error = validateParties(parties);
    if (error != null) throw ExperienceFailure(error);
    final ids = current.parties.map((party) => party.id).toSet();
    if (parties.any((party) => party.id != null && !ids.contains(party.id))) {
      throw const ExperienceFailure('当事人记录不属于此体验案件');
    }
    _cases[caseId] = current.copyWith(
      updatedAt: _now().toUtc(),
      parties: parties
          .map(
            (party) => party.id == null
                ? party.identified('demo-party-${++_sequence}')
                : party,
          )
          .toList(),
    );
  }

  @override
  Future<void> remove(String caseId) async {
    _record(caseId);
    _cases.remove(caseId);
  }

  /// 更新虚构资料及案件排序时间；校验失败保留原快照和关联数据。
  @override
  Future<void> saveSupplement(String caseId, CaseSupplement value) async {
    final record = _record(caseId);
    if (value.error != null) throw ExperienceFailure(value.error!);
    _cases[caseId] = record.copyWith(
      supplement: value.normalized,
      updatedAt: _now().toUtc(),
    );
  }

  @override
  Future<void> addTask(String caseId, String title) async {
    final fields = TaskFields(title: title);
    if (fields.error != null) throw ExperienceFailure(fields.error!);
    final record = _record(caseId);
    _cases[caseId] = record.copyWith(
      tasks: [
        ...record.tasks,
        ExperienceTask(id: 'demo-${++_sequence}', title: title.trim()),
      ],
    );
  }

  /// 只编辑本案任务资料，保留状态、身份、其他任务及案件更新时间。
  @override
  Future<void> updateTask(
    String caseId,
    String taskId,
    TaskFields fields,
  ) async {
    final record = _record(caseId);
    if (!record.tasks.any((task) => task.id == taskId)) {
      throw const ExperienceFailure('体验任务不存在');
    }
    if (fields.error != null) throw ExperienceFailure(fields.error!);
    _cases[caseId] = record.copyWith(
      tasks: record.tasks
          .map(
            (task) => task.id == taskId
                ? task.copyWith(fields: fields.normalized)
                : task,
          )
          .toList(),
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
            (task) =>
                task.id == taskId ? task.copyWith(done: !task.done) : task,
          )
          .toList(),
    );
  }

  @override
  Future<void> addSample(String caseId, {String category = 'EVIDENCE'}) async {
    if (!documentCategories.containsKey(category)) {
      throw const ExperienceFailure('请选择有效分类');
    }
    final record = _record(caseId);
    final key = '$caseId:$category';
    final version = (_versions[key] ?? 0) + 1;
    _versions[key] = version;
    _cases[caseId] = record.copyWith(
      files: [
        ...record.files,
        ExperienceFile(
          id: 'demo-${++_sequence}',
          version: version,
          category: category,
        ),
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
