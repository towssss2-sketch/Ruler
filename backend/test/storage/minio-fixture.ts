import { CreateBucketCommand, DeleteBucketCommand, DeleteObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { randomUUID } from 'node:crypto';
import { loadStorageConfig, MinioConfig } from '../../src/modules/document/storage/storage-config';
import { S3Driver } from '../../src/modules/document/storage/s3-driver';
import { UploadRequest } from '../../src/modules/document/storage/storage.service';
import { fictionalContent, uploadInput } from './fixtures';

export let config: MinioConfig;
export let driver: S3Driver;
const bucket = `ruler-storage-test-${randomUUID()}`;
const keys = new Set<string>();
let client: S3Client;
let created = false;

/** 只在本机 MinIO 创建本次随机测试桶，最后只删除本次对象和该桶。 */
export function installStorageFixture(): void {
  beforeAll(async (): Promise<void> => {
    const loaded = loadStorageConfig({ ...process.env, NODE_ENV: 'test', STORAGE_DRIVER: 'minio', STORAGE_BUCKET: bucket });
    if (loaded.driver !== 'minio') throw new Error('拒绝连接非本机存储');
    config = loaded;
    client = new S3Client({ endpoint: config.endpoint, region: config.region, forcePathStyle: true,
      credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey } });
    driver = new S3Driver(config);
    try { await client.send(new CreateBucketCommand({ Bucket: bucket })); created = true; }
    catch { throw new Error('本机测试桶创建失败（未输出 SDK 内容）'); }
  });
  afterAll(async (): Promise<void> => {
    try {
      if (created) {
        for (const key of keys) await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
        await client.send(new DeleteBucketCommand({ Bucket: bucket }));
      }
    } catch { throw new Error('本次虚构测试桶清理失败（未输出 SDK 内容）'); }
    finally { driver?.close(); client?.destroy(); }
  });
}

/** 登记本次对象键以便精确清理，不扫描或清空已有开发桶。 */
export function trackedInput(name?: string): UploadRequest {
  const input = uploadInput(name);
  keys.add(input.key);
  return input;
}

/** HTTP 失败只抛固定错误；绝不让 fetch 将签名地址写入 Jest 堆栈。 */
export async function storageFetch(url: string, init?: RequestInit): Promise<Response> {
  try { return await fetch(url, { ...init, redirect: 'error', signal: AbortSignal.timeout(10000) }); }
  catch { throw new Error('本机存储 HTTP 请求失败（签名地址已隐藏）'); }
}

/** 用驱动真实签发 PUT，并通过 HTTP 直传虚构内容；不通过 SDK 绕过签名验证。 */
export async function upload(): Promise<UploadRequest> {
  const input = trackedInput();
  const signed = await driver.getUploadUrl(input);
  const response = await storageFetch(signed.url, { method: signed.method, headers: signed.headers, body: fictionalContent });
  expect(response.status).toBe(200);
  await response.arrayBuffer();
  return input;
}
