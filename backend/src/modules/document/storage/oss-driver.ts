import OSS from 'ali-oss';
import { OssConfig } from './storage-config';
import { StorageError, storageErrorCode } from './storage-error';
import { downloadDisposition, objectMetadata, uploadHeaders, validateCopy, validateKey, validateTtl } from './storage-policy';
import { SignedTransfer, StorageService, StoredObject, UploadRequest } from './storage.service';
import { hashObjectStream, validateFingerprint } from './object-fingerprint';

/** 原生 OSS 适配器；不将 OSS 当作 S3 使用。本期只验证离线 SDK 契约，真实云接入另行批准。 */
export class OssDriver extends StorageService {
  private readonly client: OSS;
  constructor(private readonly config: OssConfig, client?: OSS) {
    super(); validateTtl(config.ttlSeconds);
    this.client = client ?? new OSS({ region: config.region, endpoint: config.endpoint, bucket: config.bucket,
      accessKeyId: config.accessKeyId, accessKeySecret: config.accessKeySecret, stsToken: config.securityToken,
      secure: true, authorizationV4: true, timeout: 10000 });
  }

  /** 使用 OSS4-HMAC-SHA256，显式把 Content-Length 纳入附加签名头。 */
  async getUploadUrl(input: UploadRequest): Promise<SignedTransfer> {
    const headers = uploadHeaders(input);
    try {
      const url = await this.client.signatureUrlV4('PUT', this.config.ttlSeconds, { headers }, input.key, ['content-length']);
      return { url, method: 'PUT', headers, expiresAt: this.expiresAt() };
    } catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** 生成 HTTPS 附件下载 URL，缓存与文件名响应参数参与签名。 */
  async getDownloadUrl(key: string): Promise<SignedTransfer> {
    const disposition = downloadDisposition(key);
    try {
      const url = await this.client.signatureUrlV4('GET', this.config.ttlSeconds, { queries: {
        'response-content-disposition': disposition, 'response-cache-control': 'private, no-store',
      } }, key);
      return { url, method: 'GET', headers: {}, expiresAt: this.expiresAt() };
    } catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** 删除指定对象；固定包装错误，禁止泄露 OSS 请求响应或凭据。 */
  async delete(key: string): Promise<void> {
    validateKey(key);
    try { await this.client.delete(key); } catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** 使用原生 OSS CopyObject 与源条件头，不进行客户端明文下载中转。 */
  async copy(sourceKey: string, targetKey: string, sourceETag?: string): Promise<void> {
    validateCopy(sourceKey, targetKey, sourceETag);
    try { await this.client.copy(targetKey, sourceKey, { headers: sourceETag ? { 'x-oss-copy-source-if-match': sourceETag } : {} }); }
    catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** 仅 NoSuchKey 返回 false；桶、权限和连接错误不能当成文件不存在。 */
  async exists(key: string): Promise<boolean> { return (await this.stat(key)) !== null; }

  /** 读取 OSS HEAD 的实际对象元数据；SDK 原始结果不跨出适配层。 */
  async stat(key: string): Promise<StoredObject | null> {
    validateKey(key);
    try {
      const result = await this.client.head(key);
      const headers = result.res.headers as Record<string, unknown>;
      return objectMetadata(headers['content-length'], headers['content-type'], headers.etag);
    } catch (error: unknown) {
      if (storageErrorCode(error) === 'NoSuchKey') return null;
      throw new StorageError('UNAVAILABLE');
    }
  }

  /** 原生 OSS 条件流式读取；仅离线契约已验证，真实云仍待接入。 */
  async fingerprint(key: string, sizeBytes: number, etag: string): Promise<string> {
    validateFingerprint(key, sizeBytes, etag);
    try {
      const result = await this.client.getStream(key, { headers: { 'If-Match': etag } });
      return await hashObjectStream(result.stream, sizeBytes);
    } catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** SDK 使用共享 HTTP 客户端，不销毁全局资源；本适配器没有自建连接池。 */
  close(): void { /* 不调用全局 urllib 清理，避免影响其他 OSS 实例。 */ }
  private expiresAt(): Date { return new Date(Date.now() + this.config.ttlSeconds * 1000); }
}
