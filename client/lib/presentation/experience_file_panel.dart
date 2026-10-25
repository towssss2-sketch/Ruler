import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/experience_provider.dart';
import '../domain/experience.dart';
import '../domain/documents.dart';
import 'experience_widgets.dart';

class ExperienceFilePanel extends ConsumerStatefulWidget {
  const ExperienceFilePanel({required this.record, super.key});
  final ExperienceCase record;
  @override
  ConsumerState<ExperienceFilePanel> createState() =>
      _ExperienceFilePanelState();
}

class _ExperienceFilePanelState extends ConsumerState<ExperienceFilePanel> {
  String _category = 'EVIDENCE';

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('分类归档体验：只演示条目与版本，不读取设备文件，不执行真实上传或下载。'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _category,
        decoration: const InputDecoration(labelText: '示例材料分类'),
        isExpanded: true,
        items: documentCategories.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: (value) => setState(() => _category = value!),
      ),
      ExperienceAction(
        label: '添加示例文件版本',
        onRun: () => ref
            .read(experienceProvider.notifier)
            .addSample(widget.record.id, category: _category),
      ),
      const SizedBox(height: 16),
      if (widget.record.files.isEmpty) const Text('暂无示例文件'),
      ..._groups(),
    ],
  );

  List<Widget> _groups() => [
    for (final category in documentCategories.entries)
      if (widget.record.files.any((file) => file.category == category.key)) ...[
        Text(
          '${category.value} · ${widget.record.files.where((file) => file.category == category.key).length} 份',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ...widget.record.files.reversed
            .where((file) => file.category == category.key)
            .map(_file),
      ],
  ];

  Widget _file(ExperienceFile file) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: Text(file.name),
            subtitle: Text(
              '版本 ${file.version} · ${_current(file) ? '当前示例版本' : '历史示例版本'}',
            ),
          ),
          TextButton(onPressed: _explain, child: const Text('查看示例说明')),
          ExperienceAction(
            label: '移除此示例版本',
            onRun: () => ref
                .read(experienceProvider.notifier)
                .removeFile(widget.record.id, file.id),
          ),
        ],
      ),
    ),
  );

  bool _current(ExperienceFile file) =>
      widget.record.files.lastWhere((other) => other.group == file.group).id ==
      file.id;

  void _explain() => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('示例文件说明'),
      content: const Text(
        '这是虚构材料的列表演示，没有生成、上传或下载真实 PDF。\n真实上传分类已接入后端，需可达测试服务与账号后才能在设备体验。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
