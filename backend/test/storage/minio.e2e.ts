import { setTimeout } from 'node:timers/promises';
import { S3Driver } from '../../src/modules/document/storage/s3-driver';
import { config, driver, installStorageFixture, storageFetch, trackedInput, upload } from './minio-fixture';
import { fictionalContent } from './fixtures';
import { loopbackProxy } from './loopback-proxy';
import { loadStorageConfig } from '../../src/modules/document/storage/storage-config';

installStorageFixture();

describe('真实 MinIO 独立本机文件入口', (): void => {
  let proxy: Awaited<ReturnType<typeof loopbackProxy>>;
  let split: S3Driver;
  beforeAll(async (): Promise<void> => {
    proxy = await loopbackProxy(config.endpoint);
    const loaded = loadStorageConfig({ ...process.env, NODE_ENV: 'test', STORAGE_DRIVER: 'minio',
      STORAGE_BUCKET: config.bucket, MINIO_SIGNING_ENDPOINT: proxy.origin });
    if (loaded.driver !== 'minio') throw new Error('仅允许本机测试');
    split = new S3Driver(loaded);
  });
  afterAll(async (): Promise<void> => { split?.close(); if (proxy) await proxy.close(); });

  it('独立入口实际上传下载一致，元数据、复制和删除只访问内部地址', async (): Promise<void> => {
    const input = trackedInput();
    const put = await split.getUploadUrl(input);
    expect(new URL(put.url).origin).toBe(proxy.origin);
    const uploaded = await storageFetch(put.url, { method: 'PUT', headers: put.headers, body: fictionalContent });
    expect(uploaded.status).toBe(200); await uploaded.arrayBuffer();
    const downloaded = await storageFetch((await split.getDownloadUrl(input.key)).url);
    expect(downloaded.status).toBe(200);
    expect(Buffer.from(await downloaded.arrayBuffer()).equals(fictionalContent)).toBe(true);
    const before = [...proxy.methods];
    const metadata = await split.stat(input.key);
    const copy = trackedInput();
    await split.copy(input.key, copy.key, metadata!.etag);
    expect(await split.exists(copy.key)).toBe(true);
    await split.delete(copy.key);
    expect(await split.exists(copy.key)).toBe(false);
    expect(proxy.methods).toEqual(before);
    expect(before).toEqual(['PUT', 'GET']);
  });
  it('入口改写 Host 会被真实签名校验拒绝，失败上传不产生对象', async (): Promise<void> => {
    const source = await upload();
    const input = trackedInput();
    const put = await split.getUploadUrl(input);
    proxy.rewriteHost = true;
    try {
      const get = await storageFetch((await split.getDownloadUrl(source.key)).url);
      expect(get.status).toBe(403); await get.arrayBuffer();
      const rejected = await storageFetch(put.url, { method: 'PUT', headers: put.headers, body: fictionalContent });
      expect(rejected.status).toBe(403); await rejected.arrayBuffer();
      expect(await split.exists(input.key)).toBe(false);
    } finally { proxy.rewriteHost = false; }
  });
  it('将已签名链接直接替换为内部端口同样被拒绝，不能靠字符串替换发布', async (): Promise<void> => {
    const input = await upload();
    const signed = new URL((await split.getDownloadUrl(input.key)).url);
    const internal = new URL(config.endpoint);
    signed.host = internal.host;
    const rejected = await storageFetch(signed.toString());
    expect(rejected.status).toBe(403); await rejected.arrayBuffer();
  });
});

describe('真实 MinIO 签名读写（仅虚构文件）', (): void => {
  it('私有对象经短效 PUT 上传，再经 GET 下载；实际元数据、中文附件名和禁缓存一致', async (): Promise<void> => {
    const input = await upload();
    expect(await driver.exists(input.key)).toBe(true);
    const metadata = await driver.stat(input.key);
    expect(metadata?.sizeBytes).toBe(fictionalContent.length);
    expect(metadata?.mimeType).toBe('application/pdf');
    const signed = await driver.getDownloadUrl(input.key);
    const response = await storageFetch(signed.url);
    expect(response.status).toBe(200);
    expect(response.headers.get('content-disposition')?.includes('attachment;')).toBe(true);
    expect(response.headers.get('cache-control')).toBe('private, no-store');
    expect(Buffer.from(await response.arrayBuffer()).equals(fictionalContent)).toBe(true);
    const unsigned = new URL(signed.url); unsigned.search = '';
    const rejected = await storageFetch(unsigned.toString());
    expect(rejected.status).toBe(403);
    await rejected.arrayBuffer();
  });
  it('实际复制内容保持一致；条件 ETag 不匹配时拒绝复制；删除后不再存在', async (): Promise<void> => {
    const source = await upload();
    const target = trackedInput();
    const metadata = await driver.stat(source.key);
    await driver.copy(source.key, target.key, metadata!.etag);
    const copied = await storageFetch((await driver.getDownloadUrl(target.key)).url);
    expect(copied.status).toBe(200);
    expect(Buffer.from(await copied.arrayBuffer()).equals(fictionalContent)).toBe(true);
    const refused = trackedInput();
    await expect(driver.copy(source.key, refused.key, '"00000000000000000000000000000000"')).rejects.toMatchObject({ code: 'UNAVAILABLE' });
    expect(await driver.exists(refused.key)).toBe(false);
    await driver.delete(target.key); await driver.delete(target.key);
    expect(await driver.exists(target.key)).toBe(false);
    expect(await driver.exists(source.key)).toBe(true);
  });
  it('不存在的桶和无效凭据必须失败，不能伪装成文件不存在', async (): Promise<void> => {
    const missing = new S3Driver({ ...config, bucket: `${config.bucket}-missing` });
    const denied = new S3Driver({ ...config, secretAccessKey: 'fictional-invalid-credential' });
    try {
      await expect(missing.exists(trackedInput().key)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
      await expect(denied.exists(trackedInput().key)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
    } finally { missing.close(); denied.close(); }
  });
});

describe('真实 MinIO 拒绝篡改与过期签名', (): void => {
  it('修改签名、路径或 MIME 被拒绝，签名不成为任意对象访问凭据', async (): Promise<void> => {
    const input = await upload();
    const signed = await driver.getDownloadUrl(input.key);
    const signature = new URL(signed.url); signature.searchParams.set('X-Amz-Signature', '0'.repeat(64));
    const path = new URL(signed.url); path.pathname += 'changed';
    for (const url of [signature, path]) {
      const response = await storageFetch(url.toString()); expect(response.status).toBe(403); await response.arrayBuffer();
    }
    const put = await driver.getUploadUrl(trackedInput());
    const changed = await storageFetch(put.url, { method: 'PUT', headers: { ...put.headers, 'content-type': 'text/html' }, body: fictionalContent });
    expect(changed.status).toBe(403); await changed.arrayBuffer();
  });
  it('修改内容长度或正文摘要被拒绝；失败上传不登记为已存在对象', async (): Promise<void> => {
    const input = trackedInput();
    const signed = await driver.getUploadUrl(input);
    const longer = Buffer.concat([fictionalContent, Buffer.from('x')]);
    const lengthReply = await storageFetch(signed.url, { method: 'PUT', headers: { ...signed.headers, 'content-length': String(longer.length) }, body: longer });
    expect(lengthReply.status).toBe(403); await lengthReply.arrayBuffer();
    const changed = Buffer.from(fictionalContent); changed[0] = 0;
    const digestReply = await storageFetch(signed.url, { method: 'PUT', headers: signed.headers, body: changed });
    expect(digestReply.status).toBe(400); await digestReply.arrayBuffer();
    expect(await driver.exists(input.key)).toBe(false);
  });
  it('真实等待后过期 GET/PUT 均被 MinIO 拒绝', async (): Promise<void> => {
    const input = await upload();
    const short = new S3Driver({ ...config, ttlSeconds: 1 });
    try {
      const get = await short.getDownloadUrl(input.key);
      const put = await short.getUploadUrl(trackedInput());
      await setTimeout(2100);
      const download = await storageFetch(get.url);
      expect(download.status).toBe(403); await download.arrayBuffer();
      const uploaded = await storageFetch(put.url, { method: 'PUT', headers: put.headers, body: fictionalContent });
      expect(uploaded.status).toBe(403); await uploaded.arrayBuffer();
    } finally { short.close(); }
  });
});
