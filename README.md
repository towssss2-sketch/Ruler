# RULER

律师案件管理系统的阶段 0 基础工程。当前提供离线 Flutter 欢迎页、NestJS 健康检查、
Prisma 开发迁移、PostgreSQL/Redis/MinIO 开发服务和实际 CI。
登录、案件、文件、任务和计费等功能按原始需求后续逐项实现。

项目所有者无需阅读代码或运行命令：查看 PR 中文验收报告，下载 CI 测试包体验。
当前验证状态见 [阶段 0 验收报告](docs/阶段0验收报告.md)。

## 下载与体验

GitHub → Actions → **阶段 0 检查与测试包** → 选择本 PR 的成功运行 → Artifacts：

- `ruler-android-debug-apk`：解压后安装 `app-debug.apk`（测试签名，不是上架包）。
- `ruler-windows-test-zip`：解压下载文件，再解压其中 `ruler-windows-test.zip`；
  保留全部 DLL 和 data 文件夹，双击 `ruler_client.exe`。
  CI 额外包含官方 Visual C++ x64 运行库，避免干净开发电脑缺少 CRT DLL。
- 两个 coverage 文件包是自动检查证据，不是安装包。

打开后应看到“欢迎使用 RULER”和阶段说明，点击“查看本次交付范围”，返回，再切换系统深色主题。
本版离线运行，不上传资料；不包含登录或业务数据录入。
产物尚未生成、任务失败或跳过时，不能声称安装包可用。保留时间为 14 天。

## 开发者环境与命令

固定 Node 20.20.2、Flutter 3.38.7 / Dart 3.10.7、NestJS 10、Prisma 6；
Android 编译需要完整 JDK 17（含 javac）、SDK 36、Build Tools 35.0.0、NDK 28.2.13676358、CMake 3.22.1。
Windows 构建需要 Windows 和 Visual Studio C++ 桌面工具；Linux 不能生成 Windows 包。
依赖依据见 [依赖与环境决策](docs/阶段0依赖与环境决策.md)。

从仓库根目录（Linux x86_64 或 WSL + Docker Linux 引擎）：

```bash
node scripts/init-dev.mjs
bash scripts/prepare-minio.sh
docker compose up -d --build --wait
cd backend
npm ci
npm run prisma:generate
npm run prisma:validate
npm run db:migrate
npm run lint
npm run typecheck
npm run test:coverage
npm run test:integration
npm run build
npm start
```

`init-dev.mjs` 随机生成仅供开发的 .env，已有文件不覆盖、不打印凭据。
Compose 端口仅绑定 127.0.0.1。MinIO 使用固定官方发布包及 SHA-256 构建开发镜像，
不依赖不可访问的 MinIO 镜像仓库。构建脚本当前只支持 Linux amd64，不用于生产。

后端仅监听配置的 HOST/PORT。默认开发配置为本机 3000：
GET /health 是进程存活检查；GET /health/ready 实际查询数据库，不可用返回 503。
响应包含 code/message/data/traceId；未知接口返回 404，不回显输入或底层异常。
运行 `node --env-file=.env scripts/http-smoke.mjs` 可验证已启动服务。
仅用于开发，本基座拒绝 NODE_ENV=production。

另一个终端：

```bash
cd client
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --coverage --reporter expanded
flutter run -d windows   # 仅 Windows 开发机
flutter build windows --release --no-pub  # Windows 测试 ZIP 的编译模式，不代表正式发布
flutter build apk --debug --no-pub        # Android 测试包，无正式签名
```

停止开发服务：根目录 `docker compose down`，数据卷保留。
只有丢弃全部虚构开发数据时才使用 `docker compose down --volumes`。
迁移可重复部署；第 0 阶段仅有 EnvironmentProbe 测试表。
该迁移回退限虚构开发库：丢弃开发卷并重建。不得在生产库执行此回退。

## 云环境限制

使用既有检出，不创建 worktree。SDK 和包缓存可放在 checkout 外。
受限文件系统可使用 PUB_CACHE、XDG_CONFIG_HOME、
ANALYZER_STATE_LOCATION_OVERRIDE、ANDROID_USER_HOME 和 GRADLE_USER_HOME 指向可写目录；
不修改 HOME，不禁用 TLS 或校验。
网络需要 GitHub、npm、pub.dev、storage.googleapis.com、binaries.prisma.sh、
dl.google.com、maven.google.com、Gradle/Maven 与 Docker 官方分发域名。
本阶段无需真实云服务、法院、LLM 或支付凭据。

## 工作规程

需求基线：[RULER-原始需求-v3.md](RULER-原始需求-v3.md)；
[AGENTS.md](AGENTS.md) 与 [docs](docs/) 定义执行和验收流程。
用户未验收前不自动合并；不进行生产部署。
