import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/stage_provider.dart';

/// 每个应用实例拥有自己的路由器，避免测试和窗口共享路由状态。
class RulerApp extends StatefulWidget {
  const RulerApp({super.key});

  @override
  State<RulerApp> createState() => _RulerAppState();
}

class _RulerAppState extends State<RulerApp> {
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const WelcomePage()),
      GoRoute(path: '/scope', builder: (context, state) => const ScopePage()),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RULER',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff234e70)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff234e70),
          brightness: Brightness.dark,
        ),
      ),
      routerConfig: _router,
    );
  }
}

class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('RULER')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.balance, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    '欢迎使用 RULER',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(ref.watch(stageProvider), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  const Text(
                    '这是基础工程测试版。案件、登录、文件和任务功能尚未开发。'
                    '\n请勿输入真实当事人或案件资料。',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.push('/scope'),
                    child: const Text('查看本次交付范围'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScopePage extends StatelessWidget {
  const ScopePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本次交付范围')),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Text(
            '本测试版提供欢迎页、页面跳转和浅色/深色主题。'
            '\n\n本页面离线可用；不代表后端、数据库或业务功能已通过验收。'
            '\n\n后续阶段将逐项交付登录、案件管理、文件存储和任务功能。',
          ),
        ),
      ),
    );
  }
}
