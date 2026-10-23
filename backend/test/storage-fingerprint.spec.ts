import { createHash, randomUUID } from 'node:crypto';
import { Readable } from 'node:stream';
import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import OSS from 'ali-oss';
import { hashObjectStream, validateFingerprint } from '../src/modules/document/storage/object-fingerprint';
import { ingestionStorageKey, validateKey, downloadDisposition } from '../src/modules/document/storage/storage-policy';
import { S3Driver } from '../src/modules/document/storage/s3-driver';
import { OssDriver } from '../src/modules/document/storage/oss-driver';
import { minioConfig, ossConfig } from './storage/fixtures';

const bytes = Buffer.from('fictional stream content');
const digest = createHash('sha256').update(bytes).digest('hex');
const key = ingestionStorageKey(randomUUID(), randomUUID(), randomUUID(), '虚构.pdf');
afterEach((): void => { jest.restoreAllMocks(); jest.useRealTimers(); });

describe('归集原件流式指纹与独立命名空间', (): void => {
  it('分块读取真实字节，精确长度，完成后释放流', async (): Promise<void> => {
    const stream = Readable.from([bytes.subarray(0, 3), bytes.subarray(3)]);
    expect(await hashObjectStream(stream, bytes.length)).toBe(digest);
    expect(stream.destroyed).toBe(true);
  });
  it('长度不符、非字节块、缺流与底层异常统一拒绝并释放流', async (): Promise<void> => {
    for (const [stream, size] of [[Readable.from([bytes]), 1], [Readable.from([bytes]), 100],
      [Readable.from(['text']), 4], [Readable.from((async function* (): AsyncGenerator<Buffer> {
        yield bytes; throw new Error('fictional-private-stream');
      })()), 100]] as const) {
      await expect(hashObjectStream(stream, size)).rejects.toMatchObject({ code: 'UNAVAILABLE', message: '文件存储暂不可用' });
      expect(stream.destroyed).toBe(true);
    }
    await expect(hashObjectStream(undefined, 1)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
  });
  it('挂起流三十秒超时，销毁并返回固定错误', async (): Promise<void> => {
    jest.useFakeTimers();
    const stream = new Readable({ read(): void { /* 故意不产生数据 */ } });
    const result = expect(hashObjectStream(stream, 1)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
    await jest.advanceTimersByTimeAsync(30000); await result;
    expect(stream.destroyed).toBe(true);
  });
  it('拒绝无效长度、ETag、路径与命名空间，下载保留安全中文名', (): void => {
    expect((): void => validateKey(key)).not.toThrow();
    expect(downloadDisposition(key)).toContain(encodeURIComponent('虚构.pdf'));
    for (const bad of [key.replace('/ingestion/', '/other/'), key.replace('/1_', '/2_'), `${key}/extra`,
      key.replace('虚构.pdf', '../虚构.pdf'), key.replace('虚构.pdf', '%2f.pdf')]) {
      expect((): void => validateKey(bad)).toThrow();
    }
    for (const size of [0, -1, 0.5, 209715201, NaN]) expect((): void => validateFingerprint(key, size, 'abcd')).toThrow();
    expect((): void => validateFingerprint(key, 1, 'etag\r\n')).toThrow();
    expect((): string => ingestionStorageKey('bad', randomUUID(), randomUUID(), 'x.pdf')).toThrow();
  });
  it('S3 内部读取绑定 ETag；缺流、网络错误不泄露 SDK 信息', async (): Promise<void> => {
    const client = new S3Client({ region: 'us-east-1' });
    const send = jest.spyOn(client, 'send').mockResolvedValueOnce({ Body: Readable.from([bytes]) } as never);
    const driver = new S3Driver(minioConfig(), client);
    try {
      expect(await driver.fingerprint(key, bytes.length, '"abcd"')).toBe(digest);
      const command = send.mock.calls[0]![0] as GetObjectCommand;
      expect(command).toBeInstanceOf(GetObjectCommand);
      expect(command.input).toMatchObject({ Key: key, IfMatch: '"abcd"' });
      send.mockResolvedValueOnce({} as never).mockRejectedValueOnce(new Error('fictional-private-sdk') as never);
      for (let i = 0; i < 2; i++) await expect(driver.fingerprint(key, bytes.length, 'abcd')).rejects.toMatchObject({ code: 'UNAVAILABLE' });
      await expect(driver.fingerprint(key, 0, 'abcd')).rejects.toMatchObject({ code: 'INVALID_INPUT' });
      expect(send).toHaveBeenCalledTimes(3);
    } finally { driver.close(); }
  });
  it('OSS 原生 getStream 绑定 If-Match，仅使用离线 SDK 替身', async (): Promise<void> => {
    const config = ossConfig(); const client = new OSS({ ...config, secure: true, authorizationV4: true });
    const get = jest.spyOn(client, 'getStream').mockResolvedValueOnce({ stream: Readable.from([bytes]) } as OSS.GetStreamResult);
    const driver = new OssDriver(config, client);
    try {
      expect(await driver.fingerprint(key, bytes.length, '"abcd"')).toBe(digest);
      expect(get).toHaveBeenCalledWith(key, { headers: { 'If-Match': '"abcd"' } });
      get.mockRejectedValueOnce(new Error('fictional-private-sdk')).mockResolvedValueOnce({} as OSS.GetStreamResult);
      for (let i = 0; i < 2; i++) await expect(driver.fingerprint(key, bytes.length, 'abcd')).rejects.toMatchObject({ code: 'UNAVAILABLE' });
      await expect(driver.fingerprint(key, 0, 'abcd')).rejects.toMatchObject({ code: 'INVALID_INPUT' });
      expect(get).toHaveBeenCalledTimes(3);
    } finally { driver.close(); }
  });
});
