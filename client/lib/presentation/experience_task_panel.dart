import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/experience_provider.dart';
import '../domain/experience.dart';
import 'experience_widgets.dart';
import 'task_editor.dart';

class ExperienceTaskPanel extends ConsumerStatefulWidget {
  const ExperienceTaskPanel({required this.record, super.key});
  final ExperienceCase record;

  @override
  ConsumerState<ExperienceTaskPanel> createState() =>
      _ExperienceTaskPanelState();
}

class _ExperienceTaskPanelState extends ConsumerState<ExperienceTaskPanel> {
  final _title = TextEditingController(text: '核对虚构示例材料');

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('普通工作任务演示；不计算法定期间或发送提醒。'),
      const SizedBox(height: 12),
      TextField(
        controller: _title,
        maxLength: 255,
        decoration: const InputDecoration(labelText: '虚构任务标题'),
      ),
      ExperienceAction(
        label: '添加体验任务',
        onRun: () async {
          await ref
              .read(experienceProvider.notifier)
              .addTask(widget.record.id, _title.text);
          _title.clear();
        },
      ),
      const SizedBox(height: 16),
      if (widget.record.tasks.isEmpty) const Text('暂无体验任务'),
      for (final task in widget.record.tasks) _task(task),
    ],
  );

  Future<void> _edit(ExperienceTask task) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskEditor(
        initial: task.fields,
        offline: true,
        save: (fields) => ref
            .read(experienceProvider.notifier)
            .updateTask(widget.record.id, task.id, fields),
      ),
    );
  }

  Widget _task(ExperienceTask task) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              task.done ? Icons.check_circle : Icons.radio_button_unchecked,
            ),
            title: Text(task.title),
            subtitle: Text(task.done ? '已完成' : '待办'),
          ),
          Text(task.dueDate ?? '未设工作日期'),
          Text(
            '描述：${task.description ?? '未填写'}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          ExperienceAction(label: '编辑任务', onRun: () => _edit(task)),
          ExperienceAction(
            label: task.done ? '恢复待办' : '标记完成',
            onRun: () => ref
                .read(experienceProvider.notifier)
                .toggleTask(widget.record.id, task.id),
          ),
        ],
      ),
    ),
  );
}
