import { CreateBucketCommand, DeleteBucketCommand, DeleteObjectCommand, ListObjectsV2Command, S3Client } from '@aws-sdk/client-s3';
import { createHash, randomUUID } from 'node:crypto';
import { loadStorageConfig } from '../../src/modules/document/storage/storage-config';
import { StorageService } from '../../src/modules/document/storage/storage.service';
import { UploadOffer } from '../../src/modules/document/document-upload.service';
import { PresignInput } from '../../src/modules/document/document-input';
import { DocumentView } from '../../src/modules/document/document-policy';
import { app, installFixture, request } from '../auth/fixture';
import { storageFetch } from '../storage/minio-fixture';

export const content = Buffer.from('%PDF-1.4\nFictional document API test only.\n%%EOF');
const bucket = `ruler-document-test-${randomUUID()}`;
let client: S3Client;
let created = false;
let previousBucket: string | undefined;

/** 使用本次唯一的新桶和隔离测试库；结束仅回收本次桶，绝不清空已有桶。 */
export function installDocumentFixture(): void {
  beforeAll(async (): Promise<void> => {
    const config = loadStorageConfig({ ...process.env, STORAGE_DRIVER: 'minio', STORAGE_BUCKET: bucket });
    if (config.driver !== 'minio') throw new Error('测试仅允许本机 MinIO');
    client = new S3Client({ endpoint: config.endpoint, region: config.region, forcePathStyle: true,
      credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey } });
    try { await client.send(new CreateBucketCommand({ Bucket: bucket })); created = true; }
    catch { throw new Error('虚构文档测试桶创建失败'); }
    previousBucket = process.env.STORAGE_BUCKET;
    process.env.STORAGE_BUCKET = bucket;
  });
  installFixture();
  afterAll(async (): Promise<void> => {
    try {
      if (created && /^ruler-document-test-[a-f0-9-]{36}$/.test(bucket)) {
        let token: string | undefined;
        do {
          const page = await client.send(new ListObjectsV2Command({ Bucket: bucket, ContinuationToken: token }));
          for (const entry of page.Contents ?? []) await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: entry.Key }));
          token = page.NextContinuationToken;
        } while (token);
        await client.send(new DeleteBucketCommand({ Bucket: bucket }));
      }
    } catch { throw new Error('本次文档测试桶清理失败（未输出 SDK 内容）'); }
    finally {
      client?.destroy();
      if (previousBucket === undefined) delete process.env.STORAGE_BUCKET;
      else process.env.STORAGE_BUCKET = previousBucket;
    }
  });
}

/** 生成虚构 PDF 的受限上传申请。 */
export function uploadInput(overrides: Partial<PresignInput> = {}): PresignInput {
  return { fileName: '虚构证据.pdf', mimeType: 'application/pdf', sizeBytes: content.length,
    contentMd5: createHash('md5').update(content).digest('base64'), ...overrides };
}

/** 通过实际 HTTP 取得签名并直传到私有 MinIO，只断言状态，不输出签名。 */
export async function offer(access: string, caseId: string, input: PresignInput = uploadInput()): Promise<UploadOffer> {
  const reply = await request(`/cases/${caseId}/documents/presign`, input, access);
  expect(reply.status).toBe(201);
  const value = reply.data as unknown as UploadOffer;
  const uploaded = await storageFetch(value.url, { method: 'PUT', headers: value.headers, body: content });
  expect(uploaded.status).toBe(200);
  await uploaded.arrayBuffer();
  return value;
}

/** 完成真实签名上传和元数据登记的闭环。 */
export async function uploadDocument(access: string, caseId: string, previousDocumentId?: string): Promise<DocumentView> {
  const signed = await offer(access, caseId, uploadInput({ previousDocumentId }));
  const result = await request(`/cases/${caseId}/documents`, { uploadId: signed.uploadId, category: 'EVIDENCE' }, access);
  expect(result.status).toBe(201);
  return result.data as unknown as DocumentView;
}

/** 取得当前应用使用的真实存储端口，故障测试用 spy 精确注入单次故障。 */
export function storage(): StorageService { return app.get(StorageService); }
