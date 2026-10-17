# RULER 客户端

Flutter 3.38.7 / Dart 3.10.7，已实现离线虚构演示及真实测试 API 的登录、案件、常规任务页面。
安装与边界见仓库根目录 README 和 docs/阶段11A2A验收报告.md。默认包没有服务地址，不能直接登录。
Riverpod 管理单一内存会话，go_router 与嵌套 Navigator 处理账号隔离；Dio 5.9.0 连接已实现的 REST API。drift 缓存、设备文件选择和传输尚未接入。

开发者构建时通过 `--dart-define=RULER_API_URL=...` 注入受控 HTTPS 测试服务源地址（不含路径或凭据）；本机可 HTTP。不要把此配置任务交给项目所有者。
`tool/connected_e2e.dart` 由根目录 `scripts/test-client-api.mjs` 启动，使用隔离 Nest/PostgreSQL/Redis 验证真实网络与持久化，不依赖固定测试账号；不能单独拿它充当用户注册或服务部署脚本。
