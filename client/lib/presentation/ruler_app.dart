import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/stage_provider.dart';
import 'experience_list_page.dart';
import 'experience_detail_page.dart';
import 'online_gateway.dart';

/// 每个应用实例拥有自己的路由器，避免测试和窗口共享路由状态。
class RulerApp extends StatefulWidget {
  const RulerApp({super.key});

  @override
  State<RulerApp> createState() => _RulerAppState();
}

class _RulerAppState extends State<RulerApp> {
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const WelcomePage(),
        routes: [
          GoRoute(
            path: 'online',
            builder: (context, state) => const OnlineGateway(),
          ),
          GoRoute(
            path: 'scope',
            builder: (context, state) => const ScopePage(),
          ),
          GoRoute(
            path: 'experience',
            builder: (context, state) => const ExperienceListPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    ExperienceDetailPage(caseId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
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
                    '现在可以离线体验虚构案件、示例文件版本和工作任务。'
                    '\n不连接真实账号或云端，关闭应用后数据清除。'
                    '\n请勿输入真实当事人或案件资料。',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/experience'),
                    child: const Text('开始虚构体验'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => context.go('/online'),
                    child: const Text('测试服务登录'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
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
            '本测试版提供虚构案件多人创建、搜索与基础信息编辑、当事人增删改、11 类材料分组与示例版本、任务添加与完成/恢复，以及浅色/深色主题。'
            '\n\n本页面离线可用；不代表后端、数据库或业务功能已通过验收。'
            '\n\n离线体验数据仅保存在本次运行内存。测试服务登录入口已接真实 API：登录、案件多人创建/搜索/基础信息编辑/详情与当事人管理/利益冲突候选检查/删除及常规任务。'
            '\n\n连接版需另提供可达测试服务及虚构账号，当前默认包未配置地址。连接版已接入文件选择、分类上传和下载保存；公网体验、注册界面、离线缓存和法定期间仍未交付。',
          ),
        ),
      ),
    );
  }
}
