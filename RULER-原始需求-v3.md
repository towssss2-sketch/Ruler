# RULER · Codex 代码生成提示词（合并版 v3）

> 本文件是 RULER 项目唯一的提示词文件（原两份已合并废止），对应 1 个月冲刺版路线图。
> 使用方法：
> 1. 每次开新会话先粘贴「第 0 节 · 全局系统提示词」，再粘贴对应模块的「任务提示词」。
> 2. 严格按文末「执行顺序检查单」的顺序生成，后一个模块依赖前一个的接口定义。
> 3. 每个模块生成后人工 Review 再进入下一个，不要一次性让 AI 生成整个项目。
> 核心原则：**规则优先，AI 兜底**——能用正则/规则引擎完成的不调用大模型；大模型在本系统中只负责三件事：①材料识别分类归档 ②工作任务布置 ③内容生成（案情简介/时间轴/文书初稿）。
> 最后更新：2026-10-14

---

## 第 0 节 · 全局系统提示词（每次会话开头必贴）

```
你是一名资深全栈工程师，正在为名为 RULER 的律师案件管理系统编写生产级代码。
项目将在后续由专业程序员接手维护，因此代码质量要求高于功能实现速度。

【技术栈 - 不可变更】
- 客户端：Flutter 3.x（一套代码同时构建 Windows 桌面端和 Android 端），状态管理用 Riverpod，路由用 go_router，本地缓存用 drift(SQLite)
- 后端：Node.js 20 LTS + NestJS 10 + TypeScript 严格模式，ORM 用 Prisma
- 数据库：PostgreSQL 16（生产：阿里云 RDS PostgreSQL）
- 缓存/队列：Redis 7（生产：阿里云 Tair/Redis），用于 Refresh Token 存储、接口限流、归集管道重试队列、定时任务分布式锁
- 对象存储：开发环境 MinIO（S3 协议）；生产环境阿里云 OSS（ali-oss SDK）。
  注意：OSS 不兼容 S3 协议，必须实现 StorageService 抽象接口 + 双驱动（S3Driver / OssDriver），业务代码只依赖 StorageService 接口，禁止直接 import 任一存储 SDK
- 大模型：LlmClient 走 OpenAI 兼容协议，生产首选阿里云百炼 DashScope（通义千问），案情数据不出阿里云
- 鉴权：JWT（Access Token 2h + Refresh Token 30d，Refresh Token 存 Redis 支持吊销）
- API 风格：REST，OpenAPI 3.1 文档用 @nestjs/swagger 自动生成
- 部署目标：阿里云（ECS/ACK 容器化 + RDS + OSS + Redis + SLB；域名需 ICP 备案，开发第一周启动备案流程）

【硬性编码规范】
1. TypeScript 开启 strict: true，禁止 any（确需使用必须写注释说明原因）。
2. 所有函数必须有明确入参/出参类型；公开方法写 JSDoc（中文），说明用途、参数、返回值、可能抛出的错误。
3. 命名：变量/函数 camelCase，类/组件 PascalCase，常量 UPPER_SNAKE_CASE，文件名 kebab-case。业务术语统一用英文（case/client/document/task/deadline），禁止中英混拼变量名。
4. 每个文件不超过 400 行；单个函数不超过 60 行；超过就拆分。
5. 分层纪律：Controller 只做参数校验和转发，业务逻辑全部在 Service 层，数据库访问全部走 Prisma Repository 封装，禁止跨层调用。
6. 错误处理：自定义业务异常基类 BizException（含 code/message/httpStatus），全局 ExceptionFilter 统一返回格式 { code, message, data, traceId }。禁止把原始堆栈返回给前端。
7. 日志：用 Pino，每个请求带 traceId；禁止打印敏感字段（当事人身份证号、手机号、案情内容）——日志输出前必须过脱敏函数。
8. 安全红线（每个 PR 自查）：
   - 所有 SQL 走 Prisma 参数化，禁止字符串拼接；
   - 每个查询/修改接口必须校验资源归属与角色权限（防 IDOR 越权），做成 CaseAccessGuard 统一处理，不允许依赖开发者自觉；
   - 文件下载走后端鉴权后的预签名 URL（有效期 ≤ 10 分钟），禁止永久直链；
   - 所有入参用 class-validator DTO 校验；
   - 敏感字段（idCard/phone/rawContent/credentials/送达链接）在 Prisma Schema 注释中标记 @sensitive，落库前加密（用独立的 EncryptionService，AES-256-GCM，密钥从环境变量读取，留出国密 SM4 的替换接口）。
9. 测试：Service 层必须配单元测试（Jest，业务分支覆盖率 ≥ 80%），接口层配 e2e 测试关键路径。生成的每个模块附带测试文件。
10. 提交粒度：一个功能一个 commit，commit message 用 Conventional Commits（feat/fix/refactor/test/chore）。
11. 不要引入未在清单中的第三方依赖；确需引入时先停下来说明理由等我确认。
12. 配置项全部走环境变量 + zod 校验，禁止硬编码任何密钥/连接串/域名。
13. AI 使用纪律（项目级原则"规则优先，AI 兜底"）：
    - 能用正则/规则引擎/数据库查询完成的任务，禁止调用大模型；
    - 大模型调用全部走 LlmClient 抽象层（模型厂商经环境变量可切换），记录 Token 用量；
    - 发给大模型的内容最小化，禁止发送与任务无关的当事人敏感信息。

【输出要求】
- 按文件逐个输出，每个文件开头用注释标明路径，如 // FILE: src/modules/case/case.service.ts
- 生成完一个模块后输出：本模块文件清单、对已有代码的改动点、下一步建议
- 遇到需求歧义，先列出你的假设再继续，不要默默选一个
```

---

## 第 1 节 · 任务提示词：数据库 Schema v2

```
【任务】设计 RULER 的 PostgreSQL 数据库 Schema v2（Prisma Schema 格式），这是项目第一块基石。

【实体清单】
1. User：id, email, phone, passwordHash, name, barLicenseNo(执业证号), tier(FREE/PLUS/PREMIUM), tierExpireAt, storageQuotaBytes, storageUsedBytes
2. Case：id, ownerId(主办律师), caseNo(案号), cause(案由), court(管辖法院), judge, clerk, clerkPhone, fee(Decimal), feeStatus, stage(一审/二审/执行/再审), status(进行中/已结案), 备注
3. CaseParty：id, caseId, role(PLAINTIFF/DEFENDANT/THIRD_PARTY), name, idCard?, phone?, address?
4. CaseMember（案件协作）：id, caseId, userId, role(OWNER/EDITOR/VIEWER), invitedBy, invitedAt, acceptedAt, status(PENDING/ACCEPTED/REVOKED)；约束 (caseId, userId) 唯一；Case.ownerId 变化时同步维护
5. Document：id, caseId, category(起诉材料/答辩材料/证据材料/开庭传票/授权材料/庭审笔录/代理意见/判决书/其他), fileName, storageKey, mimeType, sizeBytes, version, isCurrentVersion, isClientVisible(默认 false，v1.1 客户门户预留), source(MANUAL/SMS/EMAIL/WECHAT), ingestionId?, uploadedBy, uploadedAt
6. IngestionRecord（材料归集记录）：id, userId, channel(SMS/EMAIL/WECHAT), rawContent(原始文本，加密), attachmentKeys(JSONB), aiResult(JSONB，AI 识别结构化结果), matchedCaseId?, status(PENDING_MATCH/MATCHED/ASSIGNED/IGNORED), receivedAt
7. Task：id, caseId, title, description, dueDate, status(TODO/DONE), source(MANUAL/AI_GENERATED/DEADLINE_RULE), isClientVisible, completedAt,
   deadlineType(APPEAL_PERIOD上诉期/EVIDENCE_PERIOD举证期/PRESERVATION_RENEWAL保全续封/ENFORCEMENT_APPLICATION申请执行期/OTHER)?,
   baseDate(基准日/送达日)?, alertDays(JSONB，默认[7,3,1]), lastAlertedAt?
8. TimelineEvent：id, caseId, eventDate, title, description, sourceDocumentId?, isAiGenerated
9. CaseAnalysis：id, caseId, summary, generatedAt, modelVersion, isConfirmed
10. DocumentDraft（AI 文书初稿）：id, caseId, docType(DEFENSE/REPRESENTATION), content(富文本 JSON), modelVersion, status(DRAFT/ADOPTED), adoptedDocumentId?, createdBy, createdAt
11. EmailBinding：id, userId, email, authType(OAUTH/APP_PASSWORD), credentials(加密), lastSyncAt, status
12. DeliveryPlatformRule（送达平台适配规则）：id, domain, province, platformName, mode(DIRECT/API_LIST/LIST_PARSE/WEBVIEW_ASSIST/MANUAL), parseRules(JSONB), enabled, successCount, failCount, lastSuccessAt, createdAt
13. ClientAccess / ClientAccessLog：v1.1 客户门户用，本期建表预留
14. AuditLog：id, userId, caseId?, action, resourceType, resourceId, detail(JSONB), ip, createdAt
15. RTWallet（RT 代币钱包）：id, userId(唯一), balance, totalCharged, totalConsumed, updatedAt
16. RTTransaction（RT 流水，只增不改）：id, walletId, type(CHARGE充值/CONSUME_STORAGE扩容/CONSUME_AI/REFUND退款/ADMIN_ADJUST人工调整), amount(带符号), balanceAfter(操作后余额快照), relatedOrderId?, relatedResourceId?, remark, createdAt
17. PriceConfig（价格配置表，运营可调不改代码）：id, itemKey(如 storage_pack_10g / ai_token_pack / rt_exchange_rate), itemType(STORAGE/AI/EXCHANGE), rtPrice, yuanPrice(Decimal)?, quota(JSONB，如 {"storageBytes":10737418240,"aiTokens":100000}), enabled, updatedAt

【要求】
- UUID 主键、createdAt/updatedAt、软删除 deletedAt
- 索引：CaseMember(userId+status)、IngestionRecord(userId+status+receivedAt)、Task(caseId+dueDate+status)、Document(caseId+category)
- 敏感字段（idCard/phone/rawContent/credentials/送达链接）注释标记 @sensitive，落库加密
- 输出：prisma/schema.prisma 完整文件 + migration 说明 + 设计决策简述
```

---

## 第 2 节 · 任务提示词：后端骨架 + 鉴权

```
【任务】基于已确认的技术栈和 Prisma Schema，生成 NestJS 后端骨架。

【范围】
1. 项目初始化：NestJS + Prisma + Pino + Swagger + zod 环境变量校验，目录按模块划分（modules/auth, user, case, document, task, ingestion, ai-analysis, drafting, collaboration, billing）
2. 鉴权模块：
   - 注册（邮箱+验证码或手机号+验证码，二选一并说明理由）
   - 登录签发 Access Token(2h) + Refresh Token(30d)，Refresh Token 落库支持吊销
   - JwtAuthGuard 全局守卫 + @CurrentUser() 装饰器
   - CaseAccessGuard：校验路径中 :caseId/:documentId/:taskId 等资源"当前用户是 owner 或 CaseMember"，按 OWNER/EDITOR/VIEWER 角色矩阵判定操作权限（矩阵见第 9 节，本期先把 Guard 框架和 OWNER 判定做出来，角色判定留接口）。资源级校验每次实时查库，不做权限缓存
3. 全局基建：统一响应格式、全局异常过滤器、请求日志拦截器（traceId 贯穿）、限流（登录/验证码接口严格限流）
4. 健康检查接口 /health（含数据库连通性）

【输出】完整目录树 + 每个文件代码 + e2e 测试（注册→登录→携带 token 访问→越权访问他人资源返回 403 的用例必须有）
```

---

## 第 3 节 · 任务提示词：案件管理模块

```
【任务】实现案件管理后端模块（modules/case）。

【接口】
- POST /cases 新建案件（含当事人列表，事务写入 Case + CaseParty）
- GET /cases 分页列表：关键词搜索（案号/当事人名/案由）、按法院/阶段/状态筛选、按更新时间排序；分"我主办的/我协作的"两组（协作字段本期可预留）
- GET /cases/:caseId 详情（含当事人、统计：文件数/未完成任务数）
- PATCH /cases/:caseId 更新
- DELETE /cases/:caseId 软删除（级联软删关联数据，事务）
- POST /cases/:caseId/conflict-check 利益冲突检查：将本案全部当事人姓名与当前用户所有历史案件的当事人做模糊匹配（pg_trgm 相似度 ≥ 0.6），返回命中案件列表

【业务规则】
- 案号格式校验（兼容 (2026)浙0302民初16812号 中式案号）
- 同一用户下案号+法院联合唯一，重复返回 409 并提示已有案件
- 所有写操作写 AuditLog

【输出】完整模块代码 + Service 单元测试 + e2e 测试
```

---

## 第 4 节 · 任务提示词：文件存储模块

```
【任务】实现文件存储后端模块（modules/document）。

【存储抽象（必须先做）】
- StorageService 接口：getUploadUrl / getDownloadUrl / delete / copy / exists，业务代码只依赖该接口
- 双驱动：S3Driver（开发，MinIO + aws-sdk v3）/ OssDriver（生产，ali-oss SDK），经环境变量 STORAGE_DRIVER 切换
- 上传/下载均走驱动生成的签名 URL（MinIO 预签名 / OSS 签名 URL，有效期 ≤ 10 分钟）

【接口】
- POST /cases/:caseId/documents/presign 获取上传预签名 URL（前端直传 S3，单文件 ≤ 200MB，mimeType 白名单：pdf/doc/docx/jpg/png/mp4）
- POST /cases/:caseId/documents 上传完成后登记元数据（category 必填，版本号自动递增；归集管道写入时带 source 与 ingestionId）
- GET /cases/:caseId/documents?category= 按分类列出（默认只返回当前版本）
- GET /documents/:documentId/download 鉴权后返回下载预签名 URL（10 分钟有效）
- PATCH /documents/:documentId/client-visibility 切换对客户可见性（写审计日志，v1.1 用，本期先做接口）
- DELETE /documents/:documentId 软删除

【业务规则】
- 存储配额校验：登记时检查 owner.storageUsedBytes + size ≤ quota，超限返回 403 + 明确提示（协作上传计 OWNER 配额）
- storageKey 规范：{ownerId}/{caseId}/{documentId}/{version}_{fileName}，杜绝路径穿越
- 文件名安全化处理（去特殊字符、防 XSS）

【输出】完整模块代码 + 测试（含配额超限、越权下载他人文件两个关键用例）
```

---

## 第 5 节 · 任务提示词：工作任务模块（含法定期间预警）

```
【任务】实现工作任务模块（modules/task），法定期间预警作为本模块的子能力，不做独立模块。

【接口】
1. 常规任务：
   - POST /cases/:caseId/tasks 手动新增
   - GET /cases/:caseId/tasks 案件内列表（按 source/status 筛选）
   - GET /tasks/today 今日汇总：今日到期 + 逾期 + 预警窗口内的法定期间任务，排序：法定期间 > 逾期 > 今日到期 > 其他
   - PATCH /tasks/:taskId 更新/勾选完成
   - DELETE /tasks/:taskId（DEADLINE_RULE 来源的任务禁止删除，只能标记完成）
2. 法定期间预警（子模块 modules/task/deadline）：
   - POST /cases/:caseId/deadlines 登记：deadlineType + baseDate(送达日) → 规则引擎自动算 dueDate：
     * 上诉期：判决 15 日 / 裁定 10 日（创建时选文书类型）
     * 举证期：法院指定期限（手动输入天数）
     * 保全续封：查封/冻结期限届满前 30 日
     * 申请执行期：生效日起 2 年
     计算逻辑独立成 DeadlineCalculator 纯函数服务，规则表可配置（YAML），禁止硬编码
   - GET /deadlines/upcoming 当前用户全部案件的临近期间（按 dueDate 升序）
   - 预警：定时任务每小时扫描，进入 alertDays 窗口（默认提前 7/3/1 天）生成提醒（站内 + 预留推送接口），同一窗口不重复（lastAlertedAt 判重）

【协作权限（与第 9 节配合）】
- OWNER/EDITOR 可增删改任务；VIEWER 只读；登记法定期间仅 OWNER/EDITOR

【输出】完整模块代码 + DeadlineCalculator 单元测试（覆盖全部期间类型与跨月/跨年边界）+ e2e 测试（预警生成与判重、DEADLINE_RULE 任务不可删除）
```

---

## 第 6 节 · 任务提示词：材料归集模块（短信/邮箱/微信 + AI 分类归档 + 任务布置）

```
【任务】实现材料归集模块（modules/ingestion）。三路渠道共用一条管道，禁止复制三份逻辑。

【大模型使用边界（本项目最重要的设计约束，必须严格遵守）】
- 下载与链路环节（短信识别、链接解析、接口调用、文件下载、案号匹配）全程纯代码，禁止调用大模型；
- 大模型在本模块只允许做两件事：
  ① 材料识别分类归档：对归集到的文件内容做识别，输出文书类型（映射 Document.category）、案件归属建议、关键日期提取；
  ② 工作任务布置：材料归档后，基于材料内容生成建议任务清单（如收到起诉状→"提交答辩状"、收到传票→"开庭准备"、收到判决书→"评估上诉"），任务不直接入库，返回前端由律师勾选确认后写入 Task（source=AI_GENERATED）；
- 规则引擎能判定的（如送达短信的文书类型明确为判决书）直接走规则登记法定期间（判决书送达→上诉期），不调大模型。

【核心抽象：IngestionPipeline 五阶段，每阶段独立服务可单测】
  1. Receive（渠道适配器，纯代码）：SmsIngestAdapter / EmailIngestAdapter / WechatIngestAdapter，统一输出 IngestionInput { userId, channel, rawContent, attachments[] }
  2. Extract（纯代码）：附件文本提取 DocumentTextExtractor（pdf 用 pdf-parse，docx 用 mammoth，图片走 OCR 接口，接口可配置）
  3. Classify（唯一允许调 LlmClient 的环节）：输入提取文本，要求结构化返回 JSON：
     { caseNo?, partyNames[], documentType, category, dates[], summary, confidence }
     规则引擎先跑（SmsRuleEngine/格式特征），规则命中则跳过本环节；confidence < 0.7 强制进待定区
  4. Match（纯代码）：案号精确匹配当前用户（含协作案件）→ 当事人姓名模糊匹配（pg_trgm ≥ 0.7）→ 命中关联案件并转正式 Document（source=渠道），未命中进待定区（PENDING_MATCH）
  5. TaskSuggest（LlmClient）：归档成功后触发，生成建议任务清单返回前端待确认；送达类文书由规则引擎直接建议期间登记，不调模型
全程写 IngestionRecord；自动匹配成功的材料在案件动态标注来源渠道，律师可一键"移出案件"退回待定区。

【SMS 通道：送达短信识别 + 链接文件自动下载（全程纯代码，禁止调模型）】
1. 客户端读取短信（Android 权限 + 12368 等送达号码白名单过滤）→ POST /ingestion/sms 上报
2. 规则引擎 SmsRuleEngine：号码白名单 + 关键词（送达/文书）+ 链接域名白名单（配置化）+ 中式案号正则 → 提取案号/法院/链接参数
3. 链接文件下载（平台适配器，按域名匹配 DeliveryPlatformRule，降级顺序执行）：
   a) API 直采（mode=API_LIST，已实测打通，首选）：人民法院在线服务全国版 zxfw.court.gov.cn：
      - 从短信 URL 的 hash 参数提取 qdbh / sdbh / sdsin（mm 可选）
      - POST https://zxfw.court.gov.cn/yzw/yzw-zxfw-sdfw/api/v1/sdfw/getWsListBySdbhNew
        Body: {"sdbh":"...","qdbh":"...","sdsin":"..."}，无需登录态（2026-10-14 实测返回 code:200）
      - 响应 data 数组每项含：c_wsmc(文书名)、c_wjgs(格式)、c_fymc(法院)、wjlj(阿里云 OSS 签名直链，直接 GET 下载 PDF)
      - 批量下载可改用 downloadAllSdws 接口（同路径前缀）
      - 令牌即权限：原始链接按敏感字段加密存储；服务端调用必须限流、带正常 UA/Referer、失败退避
   b) 直链（mode=DIRECT）：HEAD 探测 Content-Type 为文件类型 → 直接 GET
   c) 网页列表解析（mode=LIST_PARSE）：GET HTML → 按平台配置的解析规则（CSS selector/正则，配置化不硬编码）提取文件链接批量下载；规则失效自动降级并告警
   d) 核验页面辅助（mode=WEBVIEW_ASSIST）：应用内 WebView 打开，用户完成验证码/身份核验（验证码可由规则从同条短信提取自动填入），WebView 下载监听器（onDownloadStart）截获文件；禁止绕过平台核验逻辑
   e) 人工兜底（mode=MANUAL）：提示用户手动下载后"用其他应用打开"发回 RULER；该域名记入不支持名单
   每次下载记录结果（成功/降级/失败原因/命中规则），用于平台适配统计与规则失效告警
4. 下载完成的文件进入管道第 2 阶段（Extract），后续分类归档与任务布置同其他渠道

【EMAIL 通道】
- POST /ingestion/email/bind 绑定邮箱（OAuth 优先，应用专用密码兜底，credentials 加密存储）
- 后台任务每 5 分钟拉取新邮件，附件进入管道

【WECHAT 通道（双通道）】
- 文件通道（主）：Android 注册系统分享/打开 Intent（ACTION_SEND / ACTION_SEND_MULTIPLE / ACTION_VIEW，mimeType 覆盖 pdf/doc/docx/jpg/png），微信内打开文件 → 用其他应用打开/分享 → 选 RULER → 客户端 POST /ingestion/wechat 上报
- 文字通道（辅）：聊天文字无法系统级分享，保留小程序转发页承接，POST 同一接口

【接口】
- GET /ingestion/pending 待定区列表
- POST /ingestion/:id/assign 手动指派到案件（转正式 Document）
- POST /ingestion/:id/ignore 忽略
- GET /ingestion/logs 归集历史
- GET /ingestion/:id/task-suggestions 查看该批材料的建议任务清单
- POST /ingestion/:id/task-suggestions/confirm 律师勾选确认后写入 Task

【硬性要求】
- rawContent、送达链接、邮件 credentials 加密落库
- 管道每阶段失败可重试，失败记录不丢（死信队列或状态机重试）
- 同一内容判重（内容哈希），防止邮件轮询/短信重复同步入库
- 每次 LlmClient 调用记录用途（CLASSIFY/TASK_SUGGEST）、Token 用量，便于成本核算

【输出】完整模块代码 + SmsRuleEngine 单测（覆盖案号正则变体/白名单/域名匹配）+ 平台适配器单测 + 管道集成测试（mock LlmClient，覆盖：规则命中跳过 LLM/案号命中/低置信进待定区/重复判重/任务建议确认入库）
```

---

## 第 7 节 · 任务提示词：AI 案件分析服务

```
【任务】实现 AI 案件分析模块（modules/ai-analysis）。大模型调用必须走 LlmClient 抽象层（OpenAI 兼容接口，厂商经环境变量可切换），禁止把具体厂商 SDK 写死在业务代码里。

【功能】
1. POST /cases/:caseId/analysis/generate 一键生成，内部三个子任务：
   a) 案情简介：读取该案件已提取文本的文件内容 → 生成 500 字内简介
   b) 时间轴：从文件内容提取 (日期, 事件) 对 → 写入 TimelineEvent（isAiGenerated=true，可编辑）
   c) 任务建议：生成必要任务清单（补充证据/开庭/提交答辩状等）→ 暂存，律师勾选确认后写入 Task（source=AI_GENERATED）
2. POST /cases/:caseId/analysis/confirm 律师确认后落库（CaseAnalysis.isConfirmed=true）

【硬性要求】
- 大模型调用带重试（指数退避，最多 3 次）+ 超时 60s + Token 用量落库
- Prompt 独立成模板文件（prompts/ 目录）带版本号，禁止硬编码在逻辑里
- 结果落库带 modelVersion 和生成时间；响应带 disclaimer 字段："AI生成内容仅供参考，请人工核对"
- 关键字段（日期/金额/人名）要求模型以 JSON 结构化返回，解析失败兜底返回纯文本而不是报错

【输出】完整模块代码 + Prompt 模板文件 + 单元测试（mock LlmClient）
```

---

## 第 8 节 · 任务提示词：AI 文书初稿生成（答辩意见/代理意见）

```
【任务】实现 AI 文书初稿模块（modules/drafting），挂在案件分析板块。

【功能】
1. POST /cases/:caseId/drafts/generate，入参 docType（DEFENSE 答辩意见 / REPRESENTATION 代理意见）：
   - 上下文组装：案件基本信息 + 当事人 + 案情简介 + 时间轴 + 起诉材料/证据材料提取文本（Token 预算有限时按 起诉状 > 证据清单 > 时间轴 优先级截断）
   - 生成结构化文书初稿：标题、当事人信息、事实与理由、正文、尾部（此致法院、日期占位）
   - 落库 DocumentDraft（status=DRAFT），返回可编辑富文本
2. PATCH /drafts/:id 律师编辑保存
3. POST /drafts/:id/adopt 定稿：转为正式 Document（category 对应答辩/代理意见，version=1），DocumentDraft.status=ADOPTED

【硬性要求】
- Prompt 模板独立文件（prompts/defense-v1.md / prompts/representation-v1.md），必须包含：
  a) 角色设定（资深诉讼律师，按中国大陆民事诉讼文书规范）
  b) 明确禁止编造证据、法条引用必须标注"请核对条文现行有效性"
  c) 输出 JSON 结构化格式定义
- 生成结果带 disclaimer："AI 生成初稿，仅供律师修改参考，不构成最终法律文件"
- 法条引用单独成数组字段返回，前端高亮提示人工核对
- 记录 modelVersion 与 Token 用量

【输出】完整模块代码 + Prompt 模板 + 单测（mock LlmClient）+ 示例生成结果快照（fixtures）
```

---

## 第 9 节 · 任务提示词：案件协作模块

```
【任务】实现案件协作模块（modules/collaboration），多律师共同管理案件。

【权限矩阵（严格实现，写成共享常量供 CaseAccessGuard 使用）】
| 能力 | OWNER | EDITOR | VIEWER |
|---|---|---|---|
| 查看案件全部内容 | ✓ | ✓ | ✓ |
| 编辑案件基本信息 | ✓ | ✓ | ✗ |
| 上传/删除文件 | ✓ | ✓ | ✗ |
| 下载文件 | ✓ | ✓ | ✓ |
| 新增/完成任务 | ✓ | ✓ | ✗ |
| 登记法定期间 | ✓ | ✓ | ✗ |
| AI 生成（分析/文书/归集任务确认） | ✓ | ✓ | ✗ |
| 邀请/移除成员 | ✓ | ✗ | ✗ |
| 转让主办/删除案件 | ✓ | ✗ | ✗ |

【接口】
- POST /cases/:caseId/members 邀请（按手机号/邮箱查找用户，被邀请人接受后生效）
- GET /collaboration/invitations 我收到的邀请 + 接受/拒绝
- PATCH /cases/:caseId/members/:userId 变更角色（仅 OWNER）
- DELETE /cases/:caseId/members/:userId 移除（仅 OWNER；被移除者立即失去访问——资源校验实时查 CaseMember，不做权限缓存）
- POST /cases/:caseId/transfer 转让主办（仅 OWNER，事务处理 ownerId 与 CaseMember 角色）
- GET /cases 列表扩展：我主办的 + 我协作的，分开展示并标注角色

【硬性要求】
- CaseAccessGuard 按上述矩阵判定全部受保护资源的操作权限
- 存储配额与 AI Token 配额只计 OWNER（协作上传/生成消耗主办律师额度，操作前校验）
- 协作操作（邀请/接受/移除/转让/跨成员编辑）全部写 AuditLog

【输出】完整模块代码 + 权限矩阵参数化测试（每个角色 × 每个操作组合）+ e2e 测试（移除成员后立即 403）
```

---

## 第 10 节 · 任务提示词：会员与计费模块

```
【任务】实现会员计费模块（modules/billing）+ RT 虚拟代币子模块（modules/billing/rt）。

【会员权益】
- FREE：1GB 存储，案件管理+任务，AI 每月体验额度（PriceConfig 配置，如 3 次生成）
- PLUS（6元/月）：10GB 存储，AI 助手（分析/归集分类/任务布置/文书初稿），每月含定额 AI 额度
- PREMIUM（18元/月）：50GB 存储，含 PLUS 全部 + 类案检索、法定期间预警（v1.1 加客户门户），每月 AI 额度高于 PLUS
- 会员月度 AI 额度用完后、FREE 体验额度用完后，消耗 RT 继续使用

【RT 虚拟代币（合规红线，必须严格实现）】
- 单向流动：人民币充值 RT（汇率存 PriceConfig，如 1元=10RT），RT 只能消耗，禁止回兑人民币/提现/用户间转账/任何形式的二手交易——代码层不提供任何 RT 流出接口
- 用途两类，价格全部走 PriceConfig 配置化：
  ① 扩容存储包（如 10GB/月、50GB/月，按自然月计费，到期自动回收配额）
  ② AI Token 包（按次或按 token 量扣 RT：文书生成/案件分析/归集分类各设单价）
- 扣费纪律：先扣会员免费额度，再扣 RT；每次扣减写 RTTransaction（含 balanceAfter 快照），流水只增不改，余额=最新流水 balanceAfter，禁止直接 update RTWallet.balance 而不写流水
- 充值：走支付订单（CHARGE 类型），支付回调验签+幂等后才入账；退款（REFUND）仅支持未消耗部分，管理员操作并写审计日志
- 用户协议明示：RT 为单向消耗型虚拟代币，不可回兑、不可转让、不设有效期或明示有效期

【接口】
- GET /billing/plans 套餐列表
- POST /billing/orders 创建订单（会员套餐 / RT 充值包），返回支付参数
- POST /billing/webhook 支付平台回调（验签！幂等！重复回调不重复开通/入账）
- GET /billing/subscription 当前订阅状态
- GET /billing/rt/wallet RT 余额与近期流水
- GET /billing/rt/prices RT 商品价格表（读 PriceConfig）
- POST /billing/rt/purchase 用 RT 购买存储包/AI 包（事务：扣 RT + 发权益 + 写流水）
- TierGuard：@RequireTier('PREMIUM') 路由级权益校验，不足返回 403 + 升级引导

【业务规则】
- 到期降级：定时任务（每日凌晨）扫描到期会员降级 FREE，存储超限只读（可下载不可上传），提前 7/1 天通知；RT 购买的扩容包到期同理
- 订单状态机（CREATED→PAID→FULFILLED / FAILED），防重放
- LlmClient 每次调用前置扣费检查（先免费额度后 RT），不足返回 403 引导充值；调用完成后按实际 token 用量结算（预估扣费→多退少补，差额写流水）
- 支付与 RT 相关操作全部写审计日志

【输出】完整模块代码 + 测试（重点：回调验签失败/重复回调/到期降级/RT 扣费流水一致性（并发扣费不超余额）/免费额度优先于 RT/扩容包到期回收）
```

---

## 第 11 节 · 任务提示词：Flutter 客户端（Windows + Android）

```
【任务】实现 RULER Flutter 客户端，对接已完成的 REST API。

【架构要求】
- 分层：presentation(页面+Widget) / application(Riverpod Provider+用例) / domain(实体+仓库接口) / infrastructure(API 实现+drift 本地缓存)
- 网络层：dio + 拦截器（自动带 token、401 自动刷新、统一错误提示）
- 本地缓存：drift(SQLite) 缓存案件列表和任务，断网可读
- Windows 端：窗口最小 1024×720、文件拖拽上传；Android 端：文件选择器适配、后台上传用 WorkManager

【页面清单（按优先级）】
1. 登录/注册
2. 首页（AI 助手视图）：今日优先级任务列表（法定期间置顶）+ 迷你日历
3. 案件列表：搜索 + 筛选 + "我主办的/我协作的"分组（带角色标签）
4. 案件详情页（核心页）：
   - Tab1 案件分析：案情简介卡片、可滚动时间轴、AI 生成内容带角标与确认按钮、"生成答辩意见/代理意见"入口 → 富文本编辑器（flutter_quill）→ 保存/定稿；法条引用高亮+核对提示条
   - Tab2 文件存储：按分类分组，上传（拖拽/选择）、下载、版本标记、来源渠道角标（短信/邮箱/微信）
   - Tab3 工作标注：常规任务列表 + 法定期间卡片（独立醒目区域：期间类型/基准日/截止日/倒计时，7 天橙色、3 天红色）+ 登记期间表单
5. 材料归集：
   - "同步短信"按钮（首页显眼位置）：点击后读取送达短信 → 后台下载文书 → 结果页展示"已归档 X 份/待定 Y 份"，附 AI 建议任务清单供勾选确认
   - 待定区页面：未匹配材料卡片（渠道图标 + AI 识别摘要 + 置信度）→ 指派到案件（案件搜索选择器）/ 忽略
   - Android 短信权限申请引导页（说明用途，被拒时给手动转发备选指引）
   - 邮箱绑定页（OAuth 跳转 / 应用密码）
   - 微信文件接收：receive_share_intent 插件接收系统分享 Intent（支持冷/热启动），先落本地暂存再上报，弱网可重试；内置图文教程"微信内打开文件 → … → 用其他应用打开 → RULER"
6. 新建/编辑案件表单：当事人动态增删、利益冲突检查结果弹窗
7. 协作：案件详情"成员"入口（列表/邀请/角色变更/移除，仅 OWNER 可见操作）、邀请通知页
8. 设置页：会员状态、存储用量条、订阅入口、AI 用量展示

【要求】
- 深色/浅色主题，Material 3 基准
- 所有异步状态有 loading/empty/error 三态
- VIEWER 角色进入案件时全部编辑入口置灰并提示"只读权限"
- AI 生成类操作失败时保留草稿入口可重试，不吞错误
- 关键 Widget 写 widget test，Provider 写单元测试

【输出】完整目录树 + 代码 + Windows exe 与 Android apk 构建说明
```

---

## 第 12 节 · 任务提示词：交接文档（所有模块生成完后执行）

```
【任务】基于已生成的全部代码，输出 HANDOVER.md：
1. 系统架构图（Mermaid）
2. 模块依赖关系与数据流说明（重点：归集管道五阶段、平台适配器降级链、权限矩阵）
3. 环境变量清单与本地启动步骤（docker-compose 起 PostgreSQL + MinIO + Redis），以及阿里云生产部署清单（ECS/ACK + RDS + OSS + Redis + SLB + 百炼）
4. 已知技术债与简化实现清单（如实列出，不要隐瞒）
5. 后续开发建议：哪些代码是临时方案、上线前必须替换
```

---

## 附 · 执行顺序检查单
1. ☐ 第 0 节 全局系统提示词（每次会话开头必贴）
2. ☐ 第 1 节 Schema v2
3. ☐ 第 2 节 后端骨架 + 鉴权（CaseAccessGuard 框架）
4. ☐ 第 3 节 案件管理（含利益冲突检查）
5. ☐ 第 4 节 文件存储
6. ☐ 第 5 节 工作任务 + 法定期间预警
7. ☐ 第 6 节 材料归集（短信下载纯代码 + AI 分类归档与任务布置）
8. ☐ 第 7 节 AI 案件分析 + 第 8 节 文书初稿
9. ☐ 第 9 节 案件协作（补全 Guard 角色判定）
10. ☐ 第 10 节 会员计费
11. ☐ 第 11 节 Flutter 客户端
12. ☐ 第 12 节 HANDOVER.md
