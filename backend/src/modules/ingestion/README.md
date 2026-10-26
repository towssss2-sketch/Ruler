# ingestion 模块边界

阶段 6A1 已实现手动转发微信文字的待定区，不代表五阶段自动归集管道完成。

## 当前接口

- `POST /ingestion/wechat`：只接收 `{ rawContent }`，返回 id/status/duplicate；最多 10000 个 Unicode 码点，拒绝空白、零字节和未知字段。仅归一化首尾空白及 CRLF/CR 换行，保留正文内部格式。
- `GET /ingestion/pending`：本人未删除的 PENDING_MATCH 记录；`GET /ingestion/logs`：本人全部未删除归集历史。page 默认 1、pageSize 默认 20，沿用 PageInput 上限。receivedAt/id 降序、同一 RepeatableRead 快照计数/读取。
- `GET /ingestion/:id`：本人记录原文；列表只带 id/channel/status/receivedAt/最多 200 码点 preview。均不返回内部键、密文、哈希、链接字段、AI 结构或 userId。
- `POST /ingestion/:id/ignore`：只接受空对象；待定→忽略，已忽略重试幂等；已匹配/指派返回 409。保留原文、接收时间与历史，不提供删除或恢复接口。

## 授权、事务与恢复

沿用全局 JWT 实时会话校验，所有记录读写在服务端绑定 CurrentUser，不接受外部 owner/channel/status/归属/附件/AI 字段。不存在、删除及他人记录同为 403；非法 UUID 为 400。归集是用户级资源，不假造案件范围套用 CaseAccessGuard。

正文使用既有 EncryptionService AES-256-GCM，AAD 为 `IngestionRecord:<id>:rawContent`；文内链接也只存在于正文密文中，不解析、不发网络请求。判重使用按用户和 WECHAT 渠道域隔离的 HMAC-SHA-256 盲索引，不保存无密钥摘要。

接收/忽略均在事务内锁活动用户，忽略再锁记录并复查归属/状态。现有唯一约束兜底，同一正文并发提交仅创建一次。创建和状态改变同事务追加无正文审计，重复接收/重复忽略不重复记写审计。数据库或审计失败整体回滚，原文由客户端保留重试；响应丢失后同文提交返回原记录和原状态，已忽略材料不会自动回待定区。软删除后的重复提交返回 409，不静默恢复。

初次接收记录保持 RECEIVE/PENDING_MATCH，不调度未实现的后台处理，不产生 AI 摘要/置信度/任务或正式 Document。6A1 没有新增依赖或迁移；6A2A 追加两张辅助表及约束，不新增云资源或公共入口。字段密钥不能随意替换；未来密钥轮换需同时迁移正文与判重索引。

## 后续拆分

6A2A 已实现后述文件暂存接口。客户端选文件已由 6A2B1 接入；手动分类/指派并转正式 Document 已由 6A2B2 接入。6A3A 提供后述 PDF/DOCX 正文预览与规则候选；自动规则匹配、持久化提取结果/AI 分类、任务建议确认、重试队列和渠道适配仍待实现。文件分类保留现有 11 类（包括法院文件、服务合同）；不会用文字待定记录冒充文件归档。

真实法院平台、短信权限、邮箱绑定和系统分享不在本轮范围；D-05/D-06/D-08/D-10 保持原状态。

## 6A2A：文件暂存后端

- `POST /ingestion/files/presign` 接收 fileName/mimeType/sizeBytes/contentMd5；不接受案件、分类、已有文档 ID 或任意键。使用既有六种格式/200MiB 上限，返回最长十分钟的直传票据。客户端已由 6A2B1 接入该入口，真实设备仍待验收。
- `POST /ingestion/files` 仅接收 uploadId。锁用户→票据；核验实际大小/MIME/MD5，条件复制到客户端不可写的独立键，再从内部对象流按 ETag 和精确长度计算 SHA-256（单次流最多 30 秒）。没有解析正文或病毒扫描，不把 MIME/MD5 检查称为文件内容安全鉴定。
- 服务端以 `IngestionRecord:<userId>:WECHAT:file:v1` HMAC 域计算去重索引，与文字域分开。同用户同内容改名保留首份名称；不同内容、用户或文字分别保存。原文密文为“手动导入文件：安全文件名”，不是提取正文。来源仅表示手动接收微信文件，不读聊天或系统分享。
- 新增 IngestionUpload 追踪临时/正式对象及完成/清理状态，IngestionFile 保留一对一附件与同用户组合外键。永久键为 `<userId>/ingestion/<ticketId>/<objectId>/1_<name>`，不伪造案件 ID；两个键独立随机。票据身份不可更改，完成/清理结果不得回退。
- `GET /ingestion/:id/file` 返回 id/fileName/mimeType/十进制 sizeBytes；`GET /ingestion/:id/file/download` 实时授权后返回短效签名。忽略保留下载，软删除拒绝新签名；此前签名最长十分钟内仍可能有效。
- 两种上传共用用户行锁、已用容量、有效未完成票据预约和 20 张总上限。首次接收原件、配额和审计同事务提交；响应丢失重试不重复占额。复制/哈希/审计失败保留票据重试，不在提交结果未知时删除原件。
- 清理器每分钟处理最多十张到期超过一分钟的票据，按用户→票据加锁，与登记互斥。删除临时对象；仅在不存在 IngestionFile 时删除正式候选副本。失败保留票据，下轮重试；已接收、忽略或软删的原件均保留且计入配额。不提供用户删除原件/释放容量操作。

真实验证使用随机隔离数据库/Redis 前缀/MinIO 桶；原生 OSS 仍只验证离线 SDK 契约。分类和案件指派由 6A2B2 接入，继续保留 11 类。迁移向前追加，回退应用时保留新表、票据、对象、配额和字段密钥；旧应用不理解暂存额度，不能直接回退后继续开放上传，应停止写入或前向修复。

## 6A2B1：客户端附件摘要

本人待定列表与详情在原响应上新增 `file: { id, fileName, mimeType, sizeBytes } | null`；列表与附件同一查询读取，继续使用原分页快照和用户范围，不带 storageKey、contentHash、userId 或签名。文字条目为 null，旧客户端忽略新增字段；新客户端严格解析非空附件，不能把坏附件静默降级为文字。没有迁移或新增授权策略。


## 6A2B2：人工案件归档

`POST /ingestion/:id/assign` 仅接受 `{ caseId, category, revision? }`，返回正式 DocumentView，不含内部对象键。守卫复用统一 CaseAccessService，事务内按案件→用户→归集记录→票据复查。只允许本人待定附件转本人 OWNER 案件，11 类枚举全部保留。

先保存 DocumentUpload 准备票据与容量预约（不签发上传 URL）；独立 pendingKey 从未指向归集原件。第二事务复制冻结原件到规范案件键，状态 ASSIGNED/matchedCaseId/stage=MATCH、Document、容量和审计原子提交。来源沿用渠道，原件保留；新增副本计等量容量。相同案件/分类重试返回原文件，改派/其他分类/忽略/软删/无附件均拒绝。

失败有效票据复用，过期或竞争产生的孤立副本由原 DocumentCleanupService 回收，绝不回收已登记或保留原件。案件软删仍保留历史容量。不自动提取、匹配或建议任务，不提供撤回/改派。无新依赖、Schema 或公开服务。


## 6A2C：归档去向与撤回

`GET /ingestion/:id/assignment` 返回 UNASSIGNED / UNAVAILABLE 或 AVAILABLE 的当前案号、法院、分类、caseId/documentId/canWithdraw。查询同时限定本人材料、当前 OWNER 案件与活动文档；案件级联软删归集后返回 403，不返回旧摘要。

`POST /ingestion/:id/withdraw` 接收 caseId/documentId，通过统一案件授权后按案件→用户→归集加锁。只撤回当前 ASSIGNED 单一归档且无其他活动版本；文档软删除、归集回 PENDING_MATCH/matchedCaseId=null、assignmentRevision 递增、审计同事务，不触及存储或容量。重复请求读取原撤回审计但不复活忽略记录；新归档后旧文档请求冲突。

迁移新增 assignmentRevision 默认 0、非负，列表/详情增加此字段；归档 revision 缺省 0，准备与提交均核对，旧客户端对撤回后的材料不能盲目归档。重新归档只忽略已软删历史版本，创建新文档，不复活旧对象身份。阶段仍为人工 MATCH，不启动提取/AI/重试队列。

## 6A3A：按需正文预览

`POST /ingestion/:id/preview` 仅接受空对象，返回 `{ attemptId, extraction, suggestion }`，`Cache-Control: private, no-store`。本人有效归集附件可预览，包括已忽略记录；无附件、删除或他人记录均 403。忙时 429，审计/数据库失败不返回正文。接口接受的键/URL/用户覆盖一律 400。

`extraction` 为 `TEXT/text` 或 `MANUAL_REQUIRED/reason/retryable`。固定原因：`UNSUPPORTED_FORMAT`、`FILE_TOO_LARGE`、`CONTENT_LIMIT`、`NO_TEXT`、`INVALID_DOCUMENT`、`UNSUPPORTED_CONTENT`、`TIMEOUT`、`UNAVAILABLE`；只有后两者建议重试。扫描件/图片不调用 OCR，解析警告不输出部分正文，密码文件不绕过密码。原件可继续人工下载处理。

`suggestion` 仅在正文成功时返回 ruleVersion/category/reason/caseNumbers/caseNumbersTruncated/requiresConfirmation；其余为 null。开头十二个非空行（最多前 1500 字符）中的独立标题命中才给候选；跨类别标题冲突不选择。案号最多十个，仅供确认，不访问案件库匹配或计算法律日期。未命中类别为 null，不缩减原有 11 类手工选择。

有界内部读取绑定精确大小、MIME 与 If-Match，解析子进程不继承环境/输出日志；资源限制详见本轮验收报告。开始/结束审计只存固定状态与 attemptId，无正文、文件名、对象键；原 rawContent、status/stage、配额和原件均不改。进程崩溃留下开始记录，新请求可重试；本轮不是完整五阶段管道。无迁移、明文提取结果表或缓存，新依赖是原 v3 已指定的 pdf-parse/mammoth。客户端入口待 6A3B。

运行测试会先 `npm run build`，因为真实子进程执行 `dist` 下的编译入口；不能用旧 dist 冒充当前代码测试。
