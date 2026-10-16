import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/experience_provider.dart';
import '../domain/experience.dart';

class ExperienceCaseForm extends ConsumerStatefulWidget {
  const ExperienceCaseForm({super.key});

  @override
  ConsumerState<ExperienceCaseForm> createState() => _ExperienceCaseFormState();
}

class _ExperienceCaseFormState extends ConsumerState<ExperienceCaseForm> {
  final _form = GlobalKey<FormState>();
  final _caseNo = TextEditingController(text: '(2026)虚构民初1号');
  final _cause = TextEditingController(text: '虚构合同纠纷');
  final _court = TextEditingController(text: '虚构测试法院');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _caseNo.dispose();
    _cause.dispose();
    _court.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(experienceProvider.notifier)
          .create(_caseNo.text, _cause.text, _court.text);
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ExperienceFailure
              ? error.message
              : '创建未完成，请重试；表单已保留',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建虚构案件'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_caseNo, '案号', 80),
            _field(_cause, '案由', 128),
            _field(_court, '法院', 128),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? '创建中…' : '创建体验案件'),
      ),
    ],
  );

  Widget _field(TextEditingController controller, String label, int limit) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          enabled: !_busy,
          maxLength: limit,
          decoration: InputDecoration(labelText: label),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '请填写$label' : null,
        ),
      );
}
