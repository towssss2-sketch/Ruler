import { CopyObjectCommand, DeleteObjectCommand, GetObjectCommand, HeadBucketCommand, HeadObjectCommand,
  PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { MinioConfig } from './storage-config';
import { StorageError, storageErrorCode } from './storage-error';
import { downloadDisposition, objectMetadata, uploadHeaders, validateCopy, validateKey, validateTtl } from './storage-policy';
import { SignedTransfer, StorageService, StoredObject, UploadRequest } from './storage.service';
import { hashObjectStream, validateFingerprint } from './object-fingerprint';
import { readObjectStream, validateRead } from './object-reader';

/** MinIO 开发驱动：所有 SDK 调用留在适配器中，不将供应商响应或异常返回业务层。 */
export class S3Driver extends StorageService {
  private readonly client: S3Client;
  private readonly signingClient: S3Client;
  constructor(private readonly config: MinioConfig, client?: S3Client) {
    super(); validateTtl(config.ttlSeconds);
    this.client = client ?? this.createClient(config.endpoint);
    this.signingClient = !config.signingEndpoint || config.signingEndpoint === config.endpoint
      ? this.client : this.createClient(config.signingEndpoint);
  }

  /** 两个连接使用相同桶身份和签名约束；签名客户端只计算链接，不发对象管理请求。 */
  private createClient(endpoint: string): S3Client {
    return new S3Client({ region: this.config.region, endpoint, forcePathStyle: true,
      credentials: { accessKeyId: this.config.accessKeyId, secretAccessKey: this.config.secretAccessKey },
      maxAttempts: 2, requestHandler: { connectionTimeout: 3000, requestTimeout: 10000 },
      requestChecksumCalculation: 'WHEN_REQUIRED', responseChecksumValidation: 'WHEN_REQUIRED' });
  }

  /** PUT 凭证包含签名的长度、MIME 和 MD5；不得省略或更换所返回的头。 */
  async getUploadUrl(input: UploadRequest): Promise<SignedTransfer> {
    const headers = uploadHeaders(input);
    try {
      const url = await getSignedUrl(this.signingClient, new PutObjectCommand({ Bucket: this.config.bucket, Key: input.key,
        ContentLength: input.sizeBytes, ContentType: input.mimeType, ContentMD5: input.contentMd5 }),
      { expiresIn: this.config.ttlSeconds, signableHeaders: new Set(Object.keys(headers)) });
      return { url, method: 'PUT', headers, expiresAt: this.expiresAt() };
    } catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** GET 凭证强制附件下载和禁止缓存；只签名，不推断数据库权限或对象存在性。 */
  async getDownloadUrl(key: string): Promise<SignedTransfer> {
    const disposition = downloadDisposition(key);
    try {
      const url = await getSignedUrl(this.signingClient, new GetObjectCommand({ Bucket: this.config.bucket, Key: key,
        ResponseContentDisposition: disposition, ResponseCacheControl: 'private, no-store' }), { expiresIn: this.config.ttlSeconds });
      return { url, method: 'GET', headers: {}, expiresAt: this.expiresAt() };
    } catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** 物理删除仅处理给定键；不删除桶或批量清空目录。 */
  async delete(key: string): Promise<void> {
    validateKey(key);
    try { await this.client.send(new DeleteObjectCommand({ Bucket: this.config.bucket, Key: key })); }
    catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** 按路径段编码复制源，保留中文文件名；可绑定源 ETag，防止检查后源被替换。 */
  async copy(sourceKey: string, targetKey: string, sourceETag?: string): Promise<void> {
    validateCopy(sourceKey, targetKey, sourceETag);
    try {
      await this.client.send(new CopyObjectCommand({ Bucket: this.config.bucket, Key: targetKey,
        CopySource: [this.config.bucket, ...sourceKey.split('/')].map(encodeURIComponent).join('/'), CopySourceIfMatch: sourceETag }));
    } catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** 只有确认桶存在而对象不存在时才返回 false，权限/网络错误保持失败。 */
  async exists(key: string): Promise<boolean> { return (await this.stat(key)) !== null; }

  /** 读取实际内容长度、MIME 和 ETag；404 时再核验桶，避免把缺桶误判为缺文件。 */
  async stat(key: string): Promise<StoredObject | null> {
    validateKey(key);
    try {
      const result = await this.client.send(new HeadObjectCommand({ Bucket: this.config.bucket, Key: key }));
      return objectMetadata(result.ContentLength, result.ContentType, result.ETag);
    } catch (error: unknown) {
      if (!['NotFound', 'NoSuchKey'].includes(storageErrorCode(error) ?? '')) throw new StorageError('UNAVAILABLE');
      try { await this.client.send(new HeadBucketCommand({ Bucket: this.config.bucket })); }
      catch { throw new StorageError('UNAVAILABLE'); }
      return null;
    }
  }

  /** 走内部连接读取指定对象流，IfMatch 防止读取到检查后更换的对象。 */
  async fingerprint(key: string, sizeBytes: number, etag: string): Promise<string> {
    validateFingerprint(key, sizeBytes, etag);
    try {
      const result = await this.client.send(new GetObjectCommand({ Bucket: this.config.bucket, Key: key, IfMatch: etag }));
      return await hashObjectStream(result.Body, sizeBytes);
    } catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** 正文读取仅走内部连接并绑定 ETag，超量或异常统一拒绝。 */
  async read(key: string, sizeBytes: number, etag: string): Promise<Buffer> {
    validateRead(key, sizeBytes, etag);
    try {
      const result = await this.client.send(new GetObjectCommand({ Bucket: this.config.bucket, Key: key, IfMatch: etag }));
      return await readObjectStream(result.Body, sizeBytes);
    } catch { throw new StorageError('UNAVAILABLE'); }
  }

  /** 释放 SDK 连接池；不会删除任何文件。 */
  close(): void {
    this.client.destroy();
    if (this.signingClient !== this.client) this.signingClient.destroy();
  }
  private expiresAt(): Date { return new Date(Date.now() + this.config.ttlSeconds * 1000); }
}
