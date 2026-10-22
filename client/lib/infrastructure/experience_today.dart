import '../domain/experience.dart';
import '../domain/today.dart';

/// 只汇总本进程全部虚构案件，不受案件列表搜索条件影响，不制造期间记录。
TodaySnapshot experienceToday(
  List<ExperienceCase> records,
  DateTime now,
  int page,
) {
  final date = shanghaiDate(now);
  final items = <TodayTask>[];
  for (final item in records) {
    for (final task in item.tasks) {
      if (!task.done &&
          task.dueDate != null &&
          task.dueDate!.compareTo(date) <= 0) {
        items.add(
          TodayTask(
            id: task.id,
            caseId: item.id,
            title: task.title,
            description: task.description,
            dueDate: task.dueDate!,
            source: 'MANUAL',
            caseLabel: item.caseNo,
          ),
        );
      }
    }
  }
  items.sort((a, b) {
    final date = a.dueDate.compareTo(b.dueDate);
    return date == 0 ? a.id.compareTo(b.id) : date;
  });
  return TodaySnapshot(
    items.skip((page - 1) * 20).take(20).toList(),
    items.length,
    page,
    date,
  );
}
