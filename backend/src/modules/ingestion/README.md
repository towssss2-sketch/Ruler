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

6A2A 已实现后述文件暂存接口。客户端选文件已由 6A2B1 接入；手动分类/指派并转正式 Document 已由 6A2B2 接入；自动规则匹配、文本提取/AI 分类、任务建议确认、重试队列和渠道适配仍待实现。文件分类保留现有 11 类（包括法院文件、服务合同）；不会用文字待定记录冒充文件归档。

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

`POST /ingestion/:id/assign` 仅接受 `{ caseId, category }`，返回正式 DocumentView，不含内部对象键。守卫复用统一 CaseAccessService，事务内按案件→用户→归集记录→票据复查。只允许本人待定附件转本人 OWNER 案件，11 类枚举全部保留。

先保存 DocumentUpload 准备票据与容量预约（不签发上传 URL）；独立 pendingKey 从未指向归集原件。第二事务复制冻结原件到规范案件键，状态 ASSIGNED/matchedCaseId/stage=MATCH、Document、容量和审计原子提交。来源沿用渠道，原件保留；新增副本计等量容量。相同案件/分类重试返回原文件，改派/其他分类/忽略/软删/无附件均拒绝。

失败有效票据复用，过期或竞争产生的孤立副本由原 DocumentCleanupService 回收，绝不回收已登记或保留原件。案件软删仍保留历史容量。不自动提取、匹配或建议任务，不提供撤回/改派。无新依赖、Schema 或公开服务。
