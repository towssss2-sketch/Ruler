import OSS from 'ali-oss';
import { OssDriver } from '../src/modules/document/storage/oss-driver';
import { ossConfig, uploadInput } from './storage/fixtures';

describe('原生 OSS SDK 离线签名（未接入真实云）', (): void => {
  it('使用 OSS V4，签名绑定长度、期限、附件响应与临时会话；不使用 S3 协议', async (): Promise<void> => {
    const config = ossConfig();
    const driver = new OssDriver(config);
    const input = uploadInput();
    const result = await driver.getUploadUrl(input);
    const url = new URL(result.url);
    expect(url.protocol).toBe('https:');
    expect(url.searchParams.get('x-oss-signature-version')).toBe('OSS4-HMAC-SHA256');
    expect(url.searchParams.get('x-oss-expires')).toBe('600');
    expect(url.searchParams.get('x-oss-additional-headers')).toBe('content-length');
    expect(url.searchParams.get('x-oss-security-token') === config.securityToken).toBe(true);
    expect(url.searchParams.has('x-oss-signature')).toBe(true);
    expect(result.url.includes(config.accessKeySecret)).toBe(false);
    const download = new URL((await driver.getDownloadUrl(input.key)).url);
    expect(download.searchParams.get('response-content-disposition')?.startsWith('attachment;')).toBe(true);
    expect(download.searchParams.get('response-cache-control')).toBe('private, no-store');
    driver.close();
  });
});

describe('OSS 适配器隔离契约（SDK 网络方法替身）', (): void => {
  const config = ossConfig();
  const client = new OSS({ ...config, bucket: config.bucket, secure: true, authorizationV4: true });
  const head = jest.spyOn(client, 'head');
  const copy = jest.spyOn(client, 'copy');
  const remove = jest.spyOn(client, 'delete');
  const sign = jest.spyOn(client, 'signatureUrlV4');
  const driver = new OssDriver(config, client);
  beforeEach((): void => { head.mockReset(); copy.mockReset(); remove.mockReset(); sign.mockReset(); });
  afterAll((): void => { driver.close(); jest.restoreAllMocks(); });
  it('读取元数据并使用 OSS 原生条件复制和删除', async (): Promise<void> => {
    const source = uploadInput().key;
    const target = uploadInput().key;
    head.mockResolvedValue({ res: { headers: { 'content-length': '20', 'content-type': 'application/pdf', etag: '"ABCDEF"' } } } as OSS.HeadObjectResult);
    expect(await driver.stat(source)).toEqual({ sizeBytes: 20, mimeType: 'application/pdf', etag: '"ABCDEF"' });
    expect(await driver.exists(source)).toBe(true);
    copy.mockResolvedValue({} as OSS.CopyAndPutMetaResult);
    await driver.copy(source, target, '"ABCDEF"');
    expect(copy).toHaveBeenCalledWith(target, source, { headers: { 'x-oss-copy-source-if-match': '"ABCDEF"' } });
    await driver.copy(source, target);
    expect(copy).toHaveBeenLastCalledWith(target, source, { headers: {} });
    remove.mockResolvedValue({} as OSS.DeleteResult);
    await driver.delete(target);
    expect(remove).toHaveBeenCalledWith(target);
  });
  it('仅对象缺失返回 false，缺桶、权限和网络错误均保持失败', async (): Promise<void> => {
    head.mockRejectedValueOnce({ code: 'NoSuchKey' });
    expect(await driver.exists(uploadInput().key)).toBe(false);
    for (const error of [{ code: 'NoSuchBucket' }, { code: 'AccessDenied' }, new Error('fictional-private')]) {
      head.mockRejectedValueOnce(error);
      await expect(driver.stat(uploadInput().key)).rejects.toMatchObject({ message: '文件存储暂不可用' });
    }
  });
  it('签名、删除和复制错误被包装，不返回 SDK 请求地址或异常内容', async (): Promise<void> => {
    const error = new Error('fictional-private-sdk-error');
    sign.mockRejectedValue(error); remove.mockRejectedValue(error); copy.mockRejectedValue(error);
    await expect(driver.getUploadUrl(uploadInput())).rejects.toMatchObject({ code: 'UNAVAILABLE' });
    await expect(driver.getDownloadUrl(uploadInput().key)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
    await expect(driver.delete(uploadInput().key)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
    await expect(driver.copy(uploadInput().key, uploadInput().key)).rejects.toMatchObject({ code: 'UNAVAILABLE' });
  });
});
