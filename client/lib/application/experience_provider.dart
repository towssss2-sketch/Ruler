import '../domain/case_detail.dart';
import '../domain/case_fields.dart';
import '../domain/task_fields.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/experience.dart';
import '../infrastructure/memory_experience.dart';

final experienceRepositoryProvider = Provider<ExperienceRepository>(
  (ref) => MemoryExperience(),
);

final experienceProvider =
    AsyncNotifierProvider<ExperienceController, List<ExperienceCase>>(
      ExperienceController.new,
    );

/// 离线用例状态；操作失败保留原列表，界面以安全中文消息提示重试。
class ExperienceController extends AsyncNotifier<List<ExperienceCase>> {
  ExperienceRepository get _repository =>
      ref.read(experienceRepositoryProvider);

  @override
  Future<List<ExperienceCase>> build() => _repository.load();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repository.load);
  }

  Future<String> create(
    String caseNo,
    String cause,
    String court, {
    List<CaseParty>? parties,
  }) async {
    final id = await _repository.create(caseNo, cause, court, parties: parties);
    await _refresh();
    return id;
  }

  /// 编辑当前进程的虚构案件并刷新页面；不连接服务端或持久化到磁盘。
  Future<void> editCase(String id, CaseFields fields) async {
    await _repository.update(id, fields);
    await _refresh();
  }

  /// 保存虚构名单后刷新内存快照，在线仓库不参与此流程。
  Future<void> saveParties(String id, List<CaseParty> parties) async {
    await _repository.saveParties(id, parties);
    await _refresh();
  }

  Future<void> remove(String id) async {
    await _repository.remove(id);
    await _refresh();
  }

  Future<void> saveSupplement(String id, CaseSupplement value) async {
    await _repository.saveSupplement(id, value);
    await _refresh();
  }

  Future<void> addTask(String id, String title) async {
    await _repository.addTask(id, title);
    await _refresh();
  }

  Future<void> toggleTask(String caseId, String taskId) async {
    await _repository.toggleTask(caseId, taskId);
    await _refresh();
  }

  Future<void> updateTask(
    String caseId,
    String taskId,
    TaskFields fields,
  ) async {
    await _repository.updateTask(caseId, taskId, fields);
    await _refresh();
  }

  Future<void> addSample(String id, {String category = 'EVIDENCE'}) async {
    await _repository.addSample(id, category: category);
    await _refresh();
  }

  Future<void> removeFile(String caseId, String fileId) async {
    await _repository.removeFile(caseId, fileId);
    await _refresh();
  }

  Future<void> _refresh() async => state = AsyncData(await _repository.load());
}
