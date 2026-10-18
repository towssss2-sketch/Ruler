# RULER

律师案件管理系统，已实现工程/CI、数据模型、开发鉴权、案件、文件及常规任务后端。
客户端已完成离线虚构演示，并接入真实登录、案件和常规任务接口；新增系统文件选择、上传进度/重试、新版本和下载保存；真实传输已通过 MinIO 联调，系统窗口仍待真机验收，详见 [11A2B2 验收报告](docs/阶段11A2B2验收报告.md)。真实 Dart 到后端/数据库联调已验证保存、重登及账号隔离，但可达测试服务和账号尚未交付，默认安装包不能直接登录。

项目所有者无需阅读代码或运行命令。客户端系统文件选择/保存已接入，真机验证与离线缓存尚待完成；后端状态见 [阶段 5A 验收报告](docs/阶段5A验收报告.md)。阶段 5B 仍待 D-05 法律决策，客户端独立推进。验证码仅投递虚构邮箱的进程内适配器，不发送真实邮件。真实 OSS、协作和计费未开放。

## 下载与体验

目前没有服务器和域名，按用户要求先交付[客户端测试环境方案](docs/客户端测试环境方案.md)。资源、预算、开通顺序及工程缺项已列明；没有购买或部署，手机/Windows 公网体验仍受阻。

GitHub → Actions → **RULER 检查与测试包** → 选择本 PR 的成功运行 → Artifacts：

- `ruler-android-debug-apk`：解压后安装 `app-debug.apk`（测试签名，不是上架包）。
- `ruler-windows-test-zip`：解压下载文件，再解压其中 `ruler-windows-test.zip`；
  保留全部 DLL 和 data 文件夹，双击 `ruler_client.exe`。
  CI 额外包含官方 Visual C++ x64 运行库，避免干净开发电脑缺少 CRT DLL。
- `ruler-auth-validation`：解压后双击 `auth-acceptance.html` 查看中文自动验收场景，不需要读代码。
- `ruler-case-validation`：解压后双击 `case-acceptance.html` 查看案件专项中文验收结果。
- `ruler-storage-validation`：解压后双击 `storage-acceptance.html`，区分真实 MinIO 与 OSS 离线测试。
- `ruler-document-validation`：解压后双击 `document-acceptance.html`，查看文件上传、配额、版本与权限的中文验收结果。
- `ruler-task-validation`：解压后双击 `task-acceptance.html`，查看常规任务和今日汇总的中文验收结果；法定期间计算、确认和提醒仍待阶段 5B。
- `ruler-client-experience`：解压后打开 `client-acceptance.html`，查看 71 项实际 Flutter 测试与真实 Widget 渲染截图（界面协议替身，不代表真机）。
- `ruler-client-api-validation`：解压打开 `client-api-acceptance.html`，查看真实 Dart/Dio→Nest→PostgreSQL/Redis/MinIO 的 9 个联调场景。
- coverage 文件包与 schema JSON 是自动检查证据，不是安装包。
- `ruler-preview-plan`：解压后打开 `preview-plan.html` 审阅测试环境建议和当前缺项；报告保持 BLOCKED，不代表服务已部署。原始测试记录和完整中文方案一并提供。

打开后点击“开始虚构体验”→“新建案件”→保留默认虚构信息创建；在详情试用“示例文件”“工作任务”，返回列表可搜索。切换系统深色主题可检查布局。
以上离线体验的示例文件只是条目演示，关闭应用后演示数据清除。新增“测试服务登录”入口已连接真实接口，但默认包未配置可达服务，显示尚未开放；无需为此反复下载。服务及虚构账号准备好后另提供直接点击的验收步骤。请勿输入真实资料。
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
node scripts/init-storage-dev.mjs
bash scripts/prepare-minio.sh
docker compose up -d --build --wait
cd backend
npm ci
npm run prisma:generate
npm run prisma:validate
npm run db:migrate
npm run lint
npm run typecheck
npm run test:coverage  # 单测 + 真实 HTTP e2e + 真实 MinIO；隔离 schema/Redis 前缀/临时桶
npm run test:integration
npm run test:database
npm run build
node --env-file=../.env ../scripts/prepare-storage-dev.mjs
npm start
```

`init-dev.mjs` 随机生成仅供开发的 .env，已有文件不覆盖、不打印凭据。
`init-auth-dev.mjs` 补充缺失的两把鉴权密钥与独立 FIELD_ENCRYPTION_KEY；已有字段密钥不可覆盖或遗失，否则已有密文无法解密。
`init-storage-dev.mjs` 仅补充开发存储参数。编译后 `prepare-storage-dev.mjs` 幂等创建或检查本机私有开发桶，不连接 OSS、不改既有策略或对象。StorageModule 已接入主应用；真实 OSS 尚未联调，不能据此启用生产。
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
文件接口与重试、版本、容量和清理语义见 [阶段4B文件业务约定](docs/阶段4B文件业务约定.md)。
任务接口为 POST/GET /cases/:caseId/tasks、PATCH/DELETE /tasks/:taskId 与 GET /tasks/today；仅 OWNER，日期按北京时间，任务描述加密落库，法定期间任务禁止删除且只能切换完成状态。客户端已提供同案常规任务入口；今日汇总与期间功能尚未接入。

另一个终端：

```bash
cd client
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --no-pub
flutter test --no-pub --coverage --reporter expanded
flutter run -d windows   # 仅 Windows 开发机
flutter build windows --release --no-pub  # Windows 测试 ZIP 的编译模式，不代表正式发布
flutter build apk --debug --no-pub        # Android 测试包，无正式签名
```

Linux 中文测试截图使用系统 Noto CJK，可通过 RULER_TEST_CJK_FONT 指定字体路径。CI 显式准备中文测试字体，将 Flutter --machine 事件交给 scripts/render-client-report.mjs 生成真实报告；无需新增应用字体或第三方 SDK。

停止开发服务：根目录 `docker compose down`，数据卷保留。
只有丢弃全部虚构开发数据时才使用 `docker compose down --volumes`。
阶段 1 使用 Prisma 原生多文件 schema（backend/prisma），包含 18 个业务模型及原 EnvironmentProbe。
数据库测试自动创建、验证并清理两个独立临时 schema，覆盖空库和阶段 0 升级，不重置现有数据。
迁移只向前追加，回退策略与尚未验证的生产恢复事项见阶段 1 验收报告。

## 云环境限制

开发者可在后端构建后运行 `node --test --test-reporter=tap scripts/preview-plan.test.mjs` 与 `node scripts/render-preview-plan.mjs`，校验本轮固定测试提案并生成中文报告。只用已有依赖、虚构凭据及实际编译驱动做离线检查，不读取 .env，不查 DNS，不新建或连接云资源。修改规格时须同步审阅方案、检查器与报告，不能靠修改 JSON 获得部署授权。

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

开发者真实客户端联调（先完成依赖安装及后端构建）：`node --env-file=.env scripts/test-client-api.mjs`，随后 `node scripts/render-client-api-report.mjs`。CI 将其作为必需检查；本次隔离数据库、账号、Redis 前缀和 MinIO 桶自动清理，不用于交付登录服务。

文件直传源由构建参数 `RULER_STORAGE_ORIGINS` 指定（逗号分隔的源）；默认空值不允许对象请求。非本机只接受 HTTPS，不跟随重定向，不向对象存储发送登录凭据。文件选择与保存适配器已接入，D-09 两个组件按用户对确认问题的“继续”批准并锁定版本；无需项目所有者修改这些参数。

存储开发配置增加可选 `MINIO_SIGNING_ENDPOINT`：未设置时沿用 `MINIO_ENDPOINT`，显式空值拒绝。内部对象查询/复制/删除使用后者，短效 PUT/GET 链接在前者直接签名；两个地址仍只允许本机 HTTP/HTTPS。真实 MinIO 已通过独立本机 HTTP 入口上传下载和 Host/端口篡改拒绝验证，详见 [11A2B3B1 验收报告](docs/阶段11A2B3B1验收报告.md)。这不是公共 HTTPS、可达手机服务或部署网关，所有者无需配置这些变量。
