import '../domain/case_detail.dart';
import 'case_detail_page.dart';
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

  Future<void> _parties(BuildContext context, WidgetRef ref, String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaseDetailPage(
          offline: true,
          load: () async {
            final records = await ref.read(experienceProvider.future);
            final current = records.firstWhere((item) => item.id == id);
            return CaseDetail(
              id: id,
              fields: current.fields,
              judge: current.supplement.judge,
              clerk: current.supplement.clerk,
              clerkPhone: current.supplement.clerkPhone,
              notes: current.supplement.notes,
              fee: current.supplement.fee,
              feeStatus: current.supplement.feeStatus,
              parties: current.parties,
              documentCount: current.files.length,
              pendingTaskCount: current.tasks
                  .where((task) => !task.done)
                  .length,
            );
          },
          saveParties: (parties) =>
              ref.read(experienceProvider.notifier).saveParties(id, parties),
          saveSupplement: (value) =>
              ref.read(experienceProvider.notifier).saveSupplement(id, value),
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, String id) async {
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
    await ref.read(experienceProvider.notifier).remove(id);
    if (context.mounted) context.go('/experience');
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
            label: '案件详情与当事人',
            onRun: () => _parties(context, ref, record.id),
          ),
          ExperienceAction(
            label: '移除体验案件',
            onRun: () => _remove(context, ref, record.id),
          ),
        ],
      );
}
