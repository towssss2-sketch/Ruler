export interface UploadRequest { key: string; mimeType: string; sizeBytes: number; contentMd5: string }
export interface SignedTransfer { url: string; method: 'PUT' | 'GET'; headers: Record<string, string>; expiresAt: Date }
export interface StoredObject { sizeBytes: number; mimeType: string; etag: string }

/** 存储端口：业务仅依赖本接口；调用前必须完成用户和资源授权，签名 URL 不能入库或日志。 */
export abstract class StorageService {
  /** 生成至多十分钟的上传凭证，绑定 MIME、长度和内容校验值；不代表登记成功。 */
  abstract getUploadUrl(input: UploadRequest): Promise<SignedTransfer>;
  /** 生成至多十分钟的附件下载凭证；已签发链接在到期前仍是访问凭据。 */
  abstract getDownloadUrl(key: string): Promise<SignedTransfer>;
  /** 物理删除对象，仅供经过业务授权的回收流程；不等同文档软删除。 */
  abstract delete(key: string): Promise<void>;
  /** 同桶复制，可用源 ETag 条件阻止源对象检查后发生变化；不建立数据库记录。 */
  abstract copy(sourceKey: string, targetKey: string, sourceETag?: string): Promise<void>;
  /** 判断对象是否存在；权限、网络及桶故障必须抛错，不能伪装成不存在。 */
  abstract exists(key: string): Promise<boolean>;
  /** 读取实际对象元数据用于后续登记校验；仅对象不存在时返回 null。 */
  abstract stat(key: string): Promise<StoredObject | null>;
  /** 从内部对象流计算 SHA-256，绑定长度及 ETag，不信任客户端提交的内容指纹。 */
  abstract fingerprint(key: string, sizeBytes: number, etag: string): Promise<string>;
  /** 内部条件读取至多 10MiB 原件，用于正文预览；不签发或接受网络 URL。 */
  abstract read(key: string, sizeBytes: number, etag: string): Promise<Buffer>;
  /** 释放本实例连接资源，不能影响其他驱动实例。 */
  abstract close(): void;
}
