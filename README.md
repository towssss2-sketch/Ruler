# RULER

律师案件管理系统的阶段 0 工程基座、阶段 1 数据模型、阶段 2 开发鉴权与阶段 3 案件管理。当前提供离线 Flutter 欢迎页、NestJS 健康检查、
Prisma 开发迁移、PostgreSQL/Redis/MinIO 开发服务和实际 CI。
邮箱验证码注册、登录、刷新、登出、资源权限验证和案件 CRUD/冲突检查接口已实现；客户端业务界面及文件、任务和计费业务仍按阶段推进。验证码仅投递给虚构测试邮箱的进程内适配器，不发送真实邮件。

项目所有者无需阅读代码或运行命令：查看 PR 中文验收报告，下载 CI 测试包体验。
当前验证状态见 [阶段 3 验收报告](docs/阶段3验收报告.md)，阶段 0 的安装体验见 [阶段 0 验收报告](docs/阶段0验收报告.md)。

## 下载与体验

GitHub → Actions → **RULER 检查与测试包** → 选择本 PR 的成功运行 → Artifacts：

- `ruler-android-debug-apk`：解压后安装 `app-debug.apk`（测试签名，不是上架包）。
- `ruler-windows-test-zip`：解压下载文件，再解压其中 `ruler-windows-test.zip`；
  保留全部 DLL 和 data 文件夹，双击 `ruler_client.exe`。
  CI 额外包含官方 Visual C++ x64 运行库，避免干净开发电脑缺少 CRT DLL。
- `ruler-auth-validation`：解压后双击 `auth-acceptance.html` 查看中文自动验收场景，不需要读代码。
- `ruler-case-validation`：解压后双击 `case-acceptance.html` 查看案件专项中文验收结果。
- coverage 文件包与 schema JSON 是自动检查证据，不是安装包。

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
node scripts/init-auth-dev.mjs
bash scripts/prepare-minio.sh
docker compose up -d --build --wait
cd backend
npm ci
npm run prisma:generate
npm run prisma:validate
npm run db:migrate
npm run lint
npm run typecheck
npm run test:coverage  # 111 单测 + 37 真实 HTTP e2e，隔离 schema/Redis 前缀
npm run test:integration
npm run test:database
npm run build
npm start
```

`init-dev.mjs` 随机生成仅供开发的 .env，已有文件不覆盖、不打印凭据。
`init-auth-dev.mjs` 补充缺失的两把鉴权密钥与独立 FIELD_ENCRYPTION_KEY；已有字段密钥不可覆盖或遗失，否则已有密文无法解密。
Compose 端口仅绑定 127.0.0.1。MinIO 使用固定官方发布包及 SHA-256 构建开发镜像，
不依赖不可访问的 MinIO 镜像仓库。构建脚本当前只支持 Linux amd64，不用于生产。

后端仅监听配置的 HOST/PORT。默认开发配置为本机 3000：
GET /health 是进程存活检查；GET /health/ready 实际查询数据库，不可用返回 503。
响应包含 code/message/data/traceId；未知接口返回 404，不回显输入或底层异常。
运行 `node --env-file=.env scripts/http-smoke.mjs` 可验证已启动服务。
鉴权默认保护所有已注册业务接口；健康检查与鉴权入口明确公开。GET /docs 提供开发 Swagger，GET /auth/me 和 /users/me 返回当前用户最小信息。资源权限验证为 /cases/:caseId/access、/documents/:documentId/access、/tasks/:taskId/access；这些不等于业务 CRUD。
邮箱方案避免短信权限与真实收费；验证码不在 HTTP、日志或公开取码接口返回。生产环境仍禁止启动。
案件真实接口包括 POST/GET /cases、GET/PATCH/DELETE /cases/:caseId、POST /cases/:caseId/conflict-check。
输入、当事人列表更新和删除保护见 [阶段3案件管理约定](docs/阶段3案件管理约定.md)。

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
阶段 1 使用 Prisma 原生多文件 schema（backend/prisma），包含 18 个业务模型及原 EnvironmentProbe。
数据库测试自动创建、验证并清理两个独立临时 schema，覆盖空库和阶段 0 升级，不重置现有数据。
迁移只向前追加，回退策略与尚未验证的生产恢复事项见阶段 1 验收报告。

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
