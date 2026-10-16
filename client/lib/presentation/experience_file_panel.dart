import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/experience_provider.dart';
import '../domain/experience.dart';
import 'experience_widgets.dart';

class ExperienceFilePanel extends ConsumerWidget {
  const ExperienceFilePanel({required this.record, super.key});
  final ExperienceCase record;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('只演示示例材料条目与版本，不读取设备文件，不执行真实上传或下载。'),
      const SizedBox(height: 12),
      ExperienceAction(
        label: '添加示例文件版本',
        onRun: () => ref.read(experienceProvider.notifier).addSample(record.id),
      ),
      const SizedBox(height: 16),
      if (record.files.isEmpty) const Text('暂无示例文件'),
      for (final file in record.files.reversed)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: Text(file.name),
                  subtitle: Text(
                    '版本 ${file.version} · '
                    '${file.id == record.files.last.id ? '当前示例版本' : '历史示例版本'}',
                  ),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('示例文件说明'),
                      content: const Text(
                        '这是虚构材料的列表演示，没有生成、上传或下载真实 PDF。'
                        '\n真实文件选择和后端直传将在后续版本接入。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('知道了'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('查看示例说明'),
                ),
                ExperienceAction(
                  label: '移除此示例版本',
                  onRun: () => ref
                      .read(experienceProvider.notifier)
                      .removeFile(record.id, file.id),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
