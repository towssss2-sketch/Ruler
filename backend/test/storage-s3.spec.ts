import { CopyObjectCommand, HeadBucketCommand, HeadObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { S3Driver } from '../src/modules/document/storage/s3-driver';
import { minioConfig, uploadInput } from './storage/fixtures';

describe('S3 驱动离线签名与错误隔离', (): void => {
  it('签名包含长度、MIME、MD5，有效期不超过十分钟；下载强制附件及无缓存', async (): Promise<void> => {
    const config = minioConfig();
    const driver = new S3Driver(config);
    try {
      const input = uploadInput();
      const result = await driver.getUploadUrl(input);
      const url = new URL(result.url);
      expect(url.searchParams.get('X-Amz-Expires')).toBe('600');
      for (const header of ['content-type', 'content-length', 'content-md5']) {
        expect(url.searchParams.get('X-Amz-SignedHeaders')?.split(';').includes(header)).toBe(true);
      }
      expect(result.headers['content-length']).toBe(String(input.sizeBytes));
      expect(result.url.includes(config.secretAccessKey)).toBe(false);
      const download = new URL((await driver.getDownloadUrl(input.key)).url);
      expect(download.searchParams.get('response-content-disposition')?.startsWith('attachment;')).toBe(true);
      expect(download.searchParams.get('response-cache-control')).toBe('private, no-store');
    } finally { driver.close(); }
  });
  it('签名凭据解析失败时仅返回固定错误，不泄露 SDK 原始异常', async (): Promise<void> => {
    const client = new S3Client({ region: 'us-east-1', credentials: async (): Promise<never> => { throw new Error('fictional-private-sdk-error'); } });
    const driver = new S3Driver(minioConfig(), client);
    try {
      await expect(driver.getUploadUrl(uploadInput())).rejects.toMatchObject({ message: '文件存储暂不可用', code: 'UNAVAILABLE' });
      await expect(driver.getDownloadUrl(uploadInput().key)).rejects.toMatchObject({ message: '文件存储暂不可用' });
    } finally { driver.close(); }
  });
});

describe('S3 驱动对象操作', (): void => {
  const client = new S3Client({ region: 'us-east-1' });
  const send = jest.spyOn(client, 'send');
  const driver = new S3Driver(minioConfig(), client);
  beforeEach((): void => { send.mockReset(); });
  afterAll((): void => { driver.close(); });
  it('读取实际元数据，中文复制源正确编码并携带条件 ETag', async (): Promise<void> => {
    const input = uploadInput();
    send.mockResolvedValue({ ContentLength: 20, ContentType: 'application/pdf', ETag: '"abcdef"' } as never);
    expect(await driver.stat(input.key)).toEqual({ sizeBytes: 20, mimeType: 'application/pdf', etag: '"abcdef"' });
    expect(await driver.exists(input.key)).toBe(true);
    await driver.copy(input.key, uploadInput().key, '"abcdef"');
    const command = send.mock.calls.at(-1)![0] as CopyObjectCommand;
    expect(command.input.CopySource?.includes('%E8%99%9A')).toBe(true);
    expect(command.input.CopySourceIfMatch).toBe('"abcdef"');
    await driver.delete(input.key);
  });
  it('对象缺失时确认桶仍存在；不存在的桶、权限和网络问题不能返回 false', async (): Promise<void> => {
    send.mockRejectedValueOnce({ name: 'NotFound' } as never).mockResolvedValueOnce({} as never);
    expect(await driver.exists(uploadInput().key)).toBe(false);
    expect(send.mock.calls[0]![0] instanceof HeadObjectCommand).toBe(true);
    expect(send.mock.calls[1]![0] instanceof HeadBucketCommand).toBe(true);
    send.mockRejectedValueOnce({ name: 'NotFound' } as never).mockRejectedValueOnce({ name: 'NoSuchBucket' } as never);
    await expect(driver.exists(uploadInput().key)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
    for (const error of [{ name: 'AccessDenied' }, new Error('fictional-private'), null]) {
      send.mockRejectedValueOnce(error as never);
      await expect(driver.exists(uploadInput().key)).rejects.toMatchObject({ message: '文件存储暂不可用' });
    }
  });
  it('缺失元数据、删除或复制故障统一失败，不向调用者附带原始 SDK 信息', async (): Promise<void> => {
    send.mockResolvedValueOnce({} as never);
    await expect(driver.stat(uploadInput().key)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
    send.mockRejectedValue(new Error('fictional-private') as never);
    await expect(driver.copy(uploadInput().key, uploadInput().key)).rejects.toMatchObject({ message: '文件存储暂不可用' });
    await expect(driver.delete(uploadInput().key)).rejects.toMatchObject({ message: '文件存储暂不可用' });
  });
});
