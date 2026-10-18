import '../domain/case_fields.dart';
import 'case_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/experience_provider.dart';
import '../domain/experience.dart';
import 'experience_file_panel.dart';
import 'experience_task_panel.dart';
import 'experience_widgets.dart';

class ExperienceDetailPage extends ConsumerWidget {
  const ExperienceDetailPage({required this.caseId, super.key});
  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('体验案件详情'),
      leading: BackButton(onPressed: () => context.go('/experience')),
    ),
    body: Column(
      children: [
        const ExperienceNotice(),
        Expanded(
          child: ref
              .watch(experienceProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => ExperienceError(
                  onRetry: () => ref.read(experienceProvider.notifier).reload(),
                ),
                data: (records) => _detail(context, ref, records),
              ),
        ),
      ],
    ),
  );

  Widget _detail(
    BuildContext context,
    WidgetRef ref,
    List<ExperienceCase> records,
  ) {
    final record = records.where((item) => item.id == caseId).firstOrNull;
    if (record == null) return const Center(child: Text('体验案件已移除'));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: '案件信息'),
                  Tab(text: '示例文件'),
                  Tab(text: '工作任务'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _summary(context, ref, record),
                    ExperienceFilePanel(record: record),
                    ExperienceTaskPanel(record: record),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, WidgetRef ref, ExperienceCase record) =>
      ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(record.cause, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text('案号：${record.caseNo}\n法院：${record.court}'),
          const SizedBox(height: 16),
          Text(
            '${record.files.length} 个示例版本\n'
            '${record.tasks.where((task) => !task.done).length} 项待办',
          ),
          Text('${caseStages[record.stage]} · ${caseStatuses[record.status]}'),
          const SizedBox(height: 24),
          ExperienceAction(
            label: '编辑案件信息',
            onRun: () async {
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => CaseEditDialog(
                  initial: record.fields,
                  offline: true,
                  save: (fields) => ref
                      .read(experienceProvider.notifier)
                      .editCase(record.id, fields),
                ),
              );
            },
          ),
          ExperienceAction(
            label: '移除体验案件',
            onRun: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('移除此体验案件？'),
                  content: const Text('仅清除本次虚构案件、任务和示例条目，不影响真实数据。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认移除'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await ref.read(experienceProvider.notifier).remove(record.id);
              if (context.mounted) context.go('/experience');
            },
          ),
        ],
      );
}
