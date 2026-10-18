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

  Future<String> create(String caseNo, String cause, String court) async {
    final id = await _repository.create(caseNo, cause, court);
    await _refresh();
    return id;
  }

  Future<void> remove(String id) async {
    await _repository.remove(id);
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
