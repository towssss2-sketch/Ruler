import 'package:flutter/material.dart';
import '../domain/today.dart';
import 'online_widgets.dart';

class TodayTaskCard extends StatelessWidget {
  const TodayTaskCard({
    required this.task,
    required this.date,
    required this.complete,
    required this.openCase,
    super.key,
  });
  final TodayTask task;
  final String date;
  final Future<void> Function() complete, openCase;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: Theme.of(context).textTheme.titleMedium),
          Text(taskSources[task.source]!),
          Text(
            '${task.timing(date)} · ${task.dueDate}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: task.remaining(date) <= 0
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          if (task.caseLabel != null) Text('所属案件：${task.caseLabel}'),
          if (task.isDeadline)
            Text(
              '${deadlineTypes[task.deadlineType]} · 基准日 ${task.baseDate}\n'
              '按服务端已确认记录展示；本页不计算、修改期限或发送提醒。',
            ),
          if (task.description != null)
            ExpansionTile(
              title: const Text('查看任务说明'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(task.description!),
                ),
              ],
            ),
          Wrap(
            spacing: 8,
            children: [
              OnlineAction(label: '标记完成', run: complete),
              OnlineAction(label: '打开所属案件', run: openCase),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<bool> confirmTodayDeadline(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('确认完成法定期间任务'),
        content: const Text('仅标记工作任务已完成并移出今日清单，不改变法律期限，也不代表已完成法律程序。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认标记完成'),
          ),
        ],
      ),
    ) ??
    false;
