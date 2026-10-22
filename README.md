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
- `ruler-client-experience`：解压后打开 `client-acceptance.html`，查看 100 项实际 Flutter 测试与真实 Widget 渲染截图（界面协议替身，不代表真机）。
- `ruler-client-api-validation`：解压打开 `client-api-acceptance.html`，查看真实 Dart/Dio→Nest→PostgreSQL/Redis/MinIO 的 11 个联调场景。
- `ruler-client-https-validation`：解压打开 `client-https-acceptance.html`，查看本机双 HTTPS 的 12 个真实客户端场景，包含两个入口的未受信任证书拒绝。临时证书仅用于本机测试，不代表公共服务或真机通过。
- `ruler-client-restricted-validation`：解压打开 `client-restricted-acceptance.html`，查看关闭注册、验证码和文档后的 12 个真实客户端场景及 12 项入口检查；仍是本机验证。
- coverage 文件包与 schema JSON 是自动检查证据，不是安装包。
- `ruler-preview-plan`：解压后打开 `preview-plan.html` 审阅测试环境建议和当前缺项；报告保持 BLOCKED，不代表服务已部署。原始测试记录和完整中文方案一并提供。

打开后点击“开始虚构体验”→“新建案件”→保留默认虚构信息创建；在详情试用“示例文件”“工作任务”，返回列表可搜索。“案件信息”新增“编辑案件信息”，可修改案号、案由、法院、阶段和状态；结案保留示例文件与待办任务。切换系统深色主题可检查布局。
示例文件页可选择 11 类材料，包含法院文件、服务合同；添加后按类别分组，版本号按各类示例分别递增。以上离线体验的示例文件只是条目演示，关闭应用后演示数据清除。新增“测试服务登录”入口已连接真实接口，但默认包未配置可达服务，显示尚未开放；无需为此反复下载。服务及虚构账号准备好后另提供直接点击的验收步骤。请勿输入真实资料。
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

本机 HTTPS：可同时提供 `RULER_TLS_CERT_FILE`、`RULER_TLS_KEY_FILE` 的绝对文件路径（材料放在仓库外）；只接受开发/测试环境和本机 HOST，证书必须有效、匹配主机且与私钥配对，每份材料限 128 KiB。未设置两项时兼容 HTTP；设置不全、空值或无效材料立即拒绝启动。最低 TLS 1.2，材料启动时加载，尚无自动续期/热更新。所有者无需配置这些变量。

开发者在原本机服务和后端构建就绪后，可执行 `node --env-file=.env scripts/test-client-api.mjs --https`，随后 `node scripts/render-client-https-report.mjs`。需要系统 OpenSSL（已在本机与 CI 验证）；脚本在临时目录生成一次性自签证书，只监听本机随机端口。默认 Dart 客户端先拒绝两个入口的未信任证书，再在工具的局部信任区运行相同应用网络层的九项业务场景。测试后关闭入口并清理证书、隔离账号、schema、Redis 前缀与桶。不会安装系统信任根或修改现有 .env。详见 [11A2B3B2 验收报告](docs/阶段11A2B3B2验收报告.md)。

### 本机隔离模式（开发者）

`RULER_RUNTIME_PROFILE` 未设置或为 `development` 时保持原开发功能；显式 `restricted-local` 时必须同时提供前述有效 TLS 材料，HOST 只能为本机，NODE_ENV 只能为 development/test。空值、拼写错误、生产或缺少 TLS 均拒绝启动，不回退为开放开发模式。模式在实例创建时固定，修改需重启。

隔离模式下注册与发验证码的处理器先于限流和业务拒绝请求（404），Swagger 页面、JSON/YAML 和静态资源不注册；既有账号登录、刷新、登出及资源权限保持原规则。此模式没有实现账号发放、到期关闭或公共网关，不能直接用于公网部署。默认开发模式仍支持原需求的注册流程。

已有本机服务及后端构建就绪后运行 `node --env-file=.env scripts/test-client-api.mjs --restricted` 和 `node scripts/render-client-https-report.mjs --restricted`。脚本通过正常注册准备随机虚构账号，关闭准备实例，重启为隔离模式，业务前后检查 12 项入口并执行 10 个真实客户端 HTTPS 场景；使用独立数据资源并清理。不会修改 .env，也不输出可交付账号。项目所有者无需运行命令或配置服务。详见 [11A2B3B3 验收报告](docs/阶段11A2B3B3验收报告.md)。

### 文件分类归档（11A2C）

原始 v3 明确要求上传分类必填、按类别查询及文件页分组。现支持：起诉材料、答辩材料、证据材料、开庭传票、授权材料、庭审笔录、代理意见、判决书、法院文件、服务合同、其他。后两种具名类别按所有者补充要求新增；开庭传票、判决书仍单列。当前是手动选择，不包含 AI 自动识别。

连接版上传不再默认为“其他”，未选择分类不能开始；从某类筛选进入上传时预选该类，新版本预选原分类，传输开始后不能改分类。列表按当前页分组，组数不是整案总数，完整结果仍按服务端分页查询。离线“开始虚构体验 → 新建案件 → 示例文件”可立即查看分类布局，真实上传仍需后续交付的可达服务和账号。

新增迁移 `20261018000000_document_categories` 只追加两个枚举值，保持原九类和旧记录不变。运行后端前先按正常流程执行迁移并生成 Prisma；更新客户端和后端需配套。不要删除新增类别、静默改成“其他”或重置库来回退。中文测试截图位于 `ruler-client-experience` 中的 `client-categories.png`、`client-category-demo.png`，详见 [分类归档验收报告](docs/阶段11A2C验收报告.md)。

### 案件基础信息编辑（11A2D）

连接版接入已有 PATCH 接口，支持修改五项基础信息，保存失败保留输入，成功后详情与列表更新；服务端当事人、备注、费用、文件和任务不随基础编辑清空。阶段和状态按实际返回显示；标记结案不会自动完成任务。离线虚构体验也可点击同一表单，只在本次内存保存。

该轮尚未交付的当事人编辑已由后续 11A2E 补齐；其他案件资料编辑已由 11A2H 补齐，公共测试服务仍未交付。真实重登、权限和冲突验证见[案件编辑验收报告](docs/阶段11A2D验收报告.md)；截图 `client-case-edit.png`、`client-case-edit-demo.png` 收入中文体验报告包。

### 案件详情与当事人（11A2E）

案件内打开“案件详情与当事人”可查看当前文件/待办统计、其他案件信息及完整名单；进入“编辑当事人”维护原告/被告/第三人的姓名和可选资料。修改保留身份，确认移除只改草稿，最后保存才同步；至少保留一人，最多一百人。写成功后读失败只重试读取，取消不提交。

“开始虚构体验”也能直接添加和修改当事人，关闭应用清除；公网服务和账号仍未交付。详情的其他案件字段编辑已由 11A2H 补齐，新建多人表单和利益冲突 UI 已由后续 11A2F 接入。点击路径、测试及回退见[当事人验收报告](docs/阶段11A2E验收报告.md)。

### 新建多人案件与利益冲突候选（11A2F）

新建时可打开“编辑新建名单”，添加原告、被告和第三人；“完成名单”仅暂存，最终创建时一次保存整份名单。离线虚构体验可直接点击，关闭应用清除。保存中的系统返回不会丢弃表单。

连接版已保存案件的详情可“检查利益冲突”，查看当前账号历史案件的姓名相似候选、已删除标记和分页。结果仅供人工核对，未命中不代表无冲突；离线不执行匹配。公共服务与账号仍未交付。操作方法、真实联调边界及回退见[多人建案与检查验收报告](docs/阶段11A2F验收报告.md)。

### 案件筛选与排序（11A2G）

案件列表的“筛选与排序”支持法院全称、审理阶段、案件状态和更新时间顺序，与案号/案由/当前当事人关键词一起生效。在线按服务端结果分页，切换条件回到第一页；取消弹窗不改变结果，清除筛选保留关键词。离线也可直接体验，编辑案件后按新的更新时间排位。

当前仍未开放公共测试服务、账号和协作组；其他案件资料编辑已由 11A2H 补齐。点击验收、实际截图与真实联调边界见[筛选排序验收报告](docs/阶段11A2G验收报告.md)。

### 案件其他资料编辑（11A2H）

打开“案件详情与当事人 → 编辑其他案件信息”，填写审判员、书记员、书记员电话、费用金额、费用状态和备注。金额最多十二位整数、两位小数，精确显示为两位小数；留空保存清除原值，0 与未填写不同。费用状态只作记录，不执行收款或付款。

保存成功后独立刷新，写失败保留草稿；取消不修改。在线沿用服务端权限、加密和审计，离线仅内存；不改变其他基础信息、当事人、文件和任务。中文步骤及测试证据见[其他资料编辑验收报告](docs/阶段11A2H验收报告.md)，实际截图 `client-case-supplement-editor.png`、`client-case-supplement-demo.png` 随本轮体验报告提供。仍无公共服务和可交付测试账号，不自动合并或部署。

### 常规任务描述与日期编辑（11A2I）

在案件工作任务中点击“编辑任务”，可修改标题、描述和工作日期。连接版新建任务也可一次填写描述；离线体验保留快捷添加标题，添加后再编辑描述和日期。任务卡显示前三行描述，完整内容可在编辑表单中查看。

日期填写 YYYY-MM-DD，必须是真实日历日期；描述/日期留空保存会清除原值。编辑保留完成状态，完成/恢复也保留描述和日期；取消不修改，写失败保留草稿，写成功后重读失败只刷新列表。在线保留当前页，修改日期可能改变任务所在页；离线只保留本次内存记录。

工作日期不等于法定期间，不计算法律期限或发送提醒，今日汇总界面仍待后续。点击验收、真实联调及截图见[常规任务编辑验收报告](docs/阶段11A2I验收报告.md)。仍无公共服务和可交付账号，不自动合并或部署。

## 今日任务汇总（阶段 11A2J）

本轮测试包从案件列表右上角“今日任务”日历图标进入；跨案件查看逾期/今日待办，打开所属案件，完成后移出清单。在线也显示服务端已有确认期间，只允许查看和确认标记完成；不提供期间计算、登记或提醒。可展开查看汇总日期所在月份。

离线体验：新建虚构案件→添加任务→编辑工作日期为当天→返回列表→点击“今日任务”。体验数据仅内存；默认包没有公共服务和测试账号。详细步骤与证据见 [阶段 11A2J 验收报告](docs/阶段11A2J验收报告.md)。新客户端需配套本轮后端的案号/法院摘要字段，无迁移或新依赖；没有自动合并或部署。
