import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/experience_provider.dart';
import '../domain/experience.dart';
import 'experience_case_form.dart';
import 'experience_widgets.dart';

class ExperienceListPage extends ConsumerStatefulWidget {
  const ExperienceListPage({super.key});

  @override
  ConsumerState<ExperienceListPage> createState() => _ExperienceListPageState();
}

class _ExperienceListPageState extends ConsumerState<ExperienceListPage> {
  String _query = '';

  Future<void> _create() async {
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ExperienceCaseForm(),
    );
    if (mounted && id != null) context.go('/experience/$id');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(experienceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的体验案件'),
        leading: BackButton(onPressed: () => context.go('/')),
        actions: [
          IconButton(
            tooltip: '刷新体验列表',
            onPressed: () => ref.read(experienceProvider.notifier).reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.isLoading ? null : _create,
        icon: const Icon(Icons.add),
        label: const Text('新建案件'),
      ),
      body: Column(
        children: [
          const ExperienceNotice(),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => ExperienceError(
                onRetry: () => ref.read(experienceProvider.notifier).reload(),
              ),
              data: _list,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<ExperienceCase> records) {
    final items = records.where(
      (item) =>
          '${item.caseNo} ${item.cause} ${item.court}'.contains(_query.trim()),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: '搜索体验案件',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 16),
            if (records.isEmpty) const Text('还没有体验案件，点击“新建案件”开始'),
            if (records.isNotEmpty && items.isEmpty) const Text('没有匹配的体验案件'),
            for (final item in items)
              Card(
                child: ListTile(
                  title: Text(item.cause),
                  subtitle: Text(
                    '${item.caseNo}\n${item.court}\n'
                    '${item.files.length} 个示例版本 · '
                    '${item.tasks.where((task) => !task.done).length} 项待办',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/experience/${item.id}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
