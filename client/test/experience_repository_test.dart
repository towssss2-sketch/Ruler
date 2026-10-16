import 'package:flutter_test/flutter_test.dart';
import 'package:ruler_client/infrastructure/memory_experience.dart';

void main() {
  registerRepositoryTest1();
  registerRepositoryTest2();
  registerRepositoryTest3();
  registerRepositoryTest4();
}

void registerRepositoryTest1() {
  test('创建、搜索所用字段与数据快照不可变；重复案件拒绝', () async {
    final repository = MemoryExperience();
    expect(await repository.load(), isEmpty);
    await repository.create('虚构1号', '虚构案由', '虚构法院');
    final snapshot = await repository.load();
    expect(snapshot.single.caseNo, '虚构1号');
    expect(() => snapshot.clear(), throwsUnsupportedError);
    expect(() => snapshot.single.tasks.clear(), throwsUnsupportedError);
    await expectLater(
      repository.create(' 虚构1号 ', '其他', '虚构法院'),
      throwsException,
    );
    await repository.create('虚构2号', '其他', '虚构法院');
    expect(snapshot.length, 1);
    expect((await repository.load()).length, 2);
  });
}

void registerRepositoryTest2() {
  test('任务完成可往返，同案隔离，不存在的任务拒绝', () async {
    final repository = MemoryExperience();
    final first = await repository.create('虚构1', '虚构', '虚构');
    final second = await repository.create('虚构2', '虚构', '虚构');
    await repository.addTask(first, ' 核对虚构材料 ');
    final records = await repository.load();
    final task = records.firstWhere((item) => item.id == first).tasks.single;
    expect(task.title, '核对虚构材料');
    await expectLater(repository.toggleTask(second, task.id), throwsException);
    await repository.toggleTask(first, task.id);
    expect((await repository.load()).last.tasks.single.done, isTrue);
    await repository.toggleTask(first, task.id);
    expect((await repository.load()).last.tasks.single.done, isFalse);
  });
}

void registerRepositoryTest3() {
  test('示例版本删除后不复用版本号，移除案件只影响该案件', () async {
    final repository = MemoryExperience();
    final first = await repository.create('虚构1', '虚构', '虚构');
    await repository.create('虚构2', '虚构', '虚构');
    await repository.addSample(first);
    final file = (await repository.load()).last.files.single;
    await repository.removeFile(first, file.id);
    await repository.addSample(first);
    expect((await repository.load()).last.files.single.version, 2);
    await repository.remove(first);
    expect((await repository.load()).single.caseNo, '虚构2');
    await expectLater(repository.addSample(first), throwsException);
  });
}

void registerRepositoryTest4() {
  test('新仓库实例没有前次数据，空输入拒绝且不留下半个任务', () async {
    final repository = MemoryExperience();
    await expectLater(repository.create('', '虚构', '虚构'), throwsException);
    final id = await repository.create('虚构', '虚构', '虚构');
    await expectLater(repository.addTask(id, ' '), throwsException);
    expect((await repository.load()).single.tasks, isEmpty);
    expect(await MemoryExperience().load(), isEmpty);
  });
}
