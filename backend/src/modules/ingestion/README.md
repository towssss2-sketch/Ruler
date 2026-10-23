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

当前记录保持 RECEIVE/PENDING_MATCH，不调度未实现的后台处理，不产生 AI 摘要/置信度/任务或正式 Document。没有新增依赖、迁移、云资源或公共入口。字段密钥不能随意替换；未来密钥轮换需同时迁移正文与判重索引。

## 后续拆分

文件接收与持久暂存票据、附件恢复、手动分类/指派并转正式 Document、自动规则匹配、文本提取/AI 分类、任务建议确认、重试队列和渠道适配仍待实现。文件分类保留现有 11 类（包括法院文件、服务合同）；不会用文字待定记录冒充文件归档。

真实法院平台、短信权限、邮箱绑定和系统分享不在本轮范围；D-05/D-06/D-08/D-10 保持原状态。
