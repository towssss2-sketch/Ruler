import 'package:flutter/material.dart';
import '../domain/online.dart';

/// 固定安全提示，不展示请求原文、堆栈或签名链接。
String onlineError(Object? error) =>
    error is ApiFailure ? error.message : '操作未完成，请刷新核对；填写内容已保留。';

/// 异步操作防连点，失败时保持原页面和输入。
class OnlineAction extends StatefulWidget {
  const OnlineAction({required this.label, required this.run, super.key});
  final String label;
  final Future<void> Function() run;
  @override
  State<OnlineAction> createState() => _OnlineActionState();
}

class _OnlineActionState extends State<OnlineAction> {
  bool _busy = false;
  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.run();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(onlineError(error))));
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

/// 明确展示网络读取的加载、错误、空状态；错误时不显示旧账号数据。
class OnlineResult<T> extends StatelessWidget {
  const OnlineResult({
    required this.future,
    required this.retry,
    required this.render,
    super.key,
  });
  final Future<T> future;
  final VoidCallback retry;
  final Widget Function(T) render;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(onlineError(snapshot.error)),
              TextButton(onPressed: retry, child: const Text('重新加载')),
            ],
          ),
        );
      }
      return render(snapshot.requireData);
    },
  );
}

/// 真实服务端分页；上一页/下一页状态来源于服务端总数。
Widget onlinePagination<T>(OnlinePage<T> result, void Function(int) go) => Wrap(
  alignment: WrapAlignment.center,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    TextButton(
      onPressed: result.page > 1 ? () => go(result.page - 1) : null,
      child: const Text('上一页'),
    ),
    Text('第 ${result.page} 页 · 共 ${result.total} 条'),
    TextButton(
      onPressed: result.hasNext ? () => go(result.page + 1) : null,
      child: const Text('下一页'),
    ),
  ],
);

/// 删除前明确确认；对话框归属连接版导航器，会话结束即销毁。
Future<bool> confirmOnlineDelete(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    ) ??
    false;
