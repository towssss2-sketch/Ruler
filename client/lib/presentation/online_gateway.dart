import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/online_provider.dart';
import '../domain/online.dart';
import 'online_cases_page.dart';
import 'online_login_page.dart';
import 'online_widgets.dart';

/// 会话变化替换嵌套导航树，避免失效或切换账号后仍看到旧详情/对话框。
class OnlineGateway extends ConsumerWidget {
  const OnlineGateway({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(onlineProvider);
    if (repository == null) return const OnlineLoginPage();
    return _Workspace(
      key: ObjectKey(repository),
      repository: repository,
      logout: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await ref.read(onlineProvider.notifier).logout();
        } catch (error) {
          if (messenger.mounted) {
            messenger.showSnackBar(SnackBar(content: Text(onlineError(error))));
          }
        }
      },
    );
  }
}

class _Workspace extends StatefulWidget {
  const _Workspace({required this.repository, required this.logout, super.key});
  final OnlineRepository repository;
  final Future<void> Function() logout;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  final _navigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (result) => _navigator.currentState!.pop(result),
    child: Navigator(
      key: _navigator,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (context) => OnlineCasesPage(
          repository: widget.repository,
          logout: widget.logout,
        ),
      ),
    ),
  );
}
