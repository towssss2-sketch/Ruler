import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/online_provider.dart';
import 'online_widgets.dart';

/// 连接真实后端的登录页；密码仅用于本次请求，不写磁盘。
class OnlineLoginPage extends ConsumerStatefulWidget {
  const OnlineLoginPage({super.key});
  @override
  ConsumerState<OnlineLoginPage> createState() => _OnlineLoginPageState();
}

class _OnlineLoginPageState extends ConsumerState<OnlineLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(onlineProvider.notifier)
          .login(_email.text.trim(), _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = onlineError(error));
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(apiOriginProvider).isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('测试账号登录')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    available
                        ? '使用已提供的虚构测试账号。保存的案件和任务保留在测试服务。'
                        : '测试服务尚未开放。此包暂不能登录，后续提供连接版测试包和虚构账号。',
                  ),
                  const Text('请勿输入真实资料。关闭应用需重新登录；注册和真实文件上传待接入。'),
                  const SizedBox(height: 20),
                  ..._fields(available),
                  if (_error != null) Text(_error!),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: available && !_busy ? _login : null,
                    child: Text(_busy ? '登录中…' : '登录测试服务'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _fields(bool available) => [
    TextFormField(
      controller: _email,
      enabled: available && !_busy,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: const InputDecoration(labelText: '虚构测试邮箱'),
      validator: (value) =>
          value != null && value.trim().endsWith('@example.invalid')
          ? null
          : '请填写已提供的 example.invalid 测试邮箱',
    ),
    TextFormField(
      controller: _password,
      enabled: available && !_busy,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(labelText: '密码'),
      validator: (value) =>
          value != null && value.length >= 12 && value.length <= 128
          ? null
          : '密码长度应为 12–128 字符',
    ),
  ];
}
