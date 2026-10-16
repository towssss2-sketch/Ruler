import 'package:flutter/material.dart';
import '../domain/experience.dart';

class ExperienceNotice extends StatelessWidget {
  const ExperienceNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.secondaryContainer,
    padding: const EdgeInsets.all(12),
    child: const Text(
      '离线虚构体验 · 不连接真实账号或云端 · 退出应用后数据清除\n'
      '请勿填写真实当事人或案件资料。示例文件仅演示列表和版本。',
    ),
  );
}

class ExperienceAction extends StatefulWidget {
  const ExperienceAction({required this.label, required this.onRun, super.key});
  final String label;
  final Future<void> Function() onRun;

  @override
  State<ExperienceAction> createState() => _ExperienceActionState();
}

class _ExperienceActionState extends State<ExperienceAction> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onRun();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ExperienceFailure ? error.message : '操作未完成，请重试；已有体验数据保留',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
    onPressed: _busy ? null : _run,
    child: Text(_busy ? '处理中…' : widget.label),
  );
}

class ExperienceError extends StatelessWidget {
  const ExperienceError({required this.onRetry, super.key});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('体验数据暂未加载，请重试'),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}
