import { randomUUID } from 'node:crypto';
import { Readable } from 'node:stream';
import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import OSS from 'ali-oss';
import { MAX_READ_BYTES, readObjectStream, validateRead } from '../src/modules/document/storage/object-reader';
import { ingestionStorageKey } from '../src/modules/document/storage/storage-policy';
import { S3Driver } from '../src/modules/document/storage/s3-driver';
import { OssDriver } from '../src/modules/document/storage/oss-driver';
import { minioConfig, ossConfig } from './storage/fixtures';

const bytes = Buffer.from('fictional bounded text');
const key = ingestionStorageKey(randomUUID(), randomUUID(), randomUUID(), '虚构.pdf');
afterEach((): void => { jest.restoreAllMocks(); jest.useRealTimers(); });
describe('正文内部读取的长度、条件与流释放', (): void => {
  it('真实分块读取精确字节，缺流/非字节/过长/过短/非法长度统一拒绝并释放流', async (): Promise<void> => {
    const stream = Readable.from([bytes.subarray(0,3), bytes.subarray(3)]);
    expect((await readObjectStream(stream,bytes.length)).equals(bytes)).toBe(true); expect(stream.destroyed).toBe(true);
    for (const [source, size] of [[Readable.from([bytes]),1],[Readable.from([bytes]),100],[Readable.from(['bad']),3],
      [Readable.from([bytes]),0],[Readable.from([bytes]),MAX_READ_BYTES+1]] as const) {
      await expect(readObjectStream(source,size)).rejects.toMatchObject({code:'UNAVAILABLE'}); expect(source.destroyed).toBe(true);
    }
    await expect(readObjectStream(undefined,1)).rejects.toMatchObject({code:'UNAVAILABLE'});
  });
  it('挂起流十秒后销毁，不允许 SDK 无限持有请求', async (): Promise<void> => {
    jest.useFakeTimers(); const source = new Readable({read(): void { /* 注入挂起流 */ }});
    const result = expect(readObjectStream(source,1)).rejects.toMatchObject({code:'UNAVAILABLE'});
    await jest.advanceTimersByTimeAsync(10000); await result; expect(source.destroyed).toBe(true);
  });
  it('本次读取独立限制 10MiB，并拒绝伪造键或条件头', (): void => {
    expect((): void => validateRead(key,MAX_READ_BYTES,'abcd')).not.toThrow();
    for (const size of [0,MAX_READ_BYTES+1,NaN]) expect((): void => validateRead(key,size,'abcd')).toThrow();
    expect((): void => validateRead('../bad',1,'abcd')).toThrow();
    expect((): void => validateRead(key,1,'bad\r\nheader')).toThrow();
  });
  it('S3 只走内部 IfMatch 读取，失败不透出 SDK 异常', async (): Promise<void> => {
    const client = new S3Client({region:'us-east-1'});
    const send = jest.spyOn(client,'send').mockResolvedValueOnce({Body:Readable.from([bytes])} as never);
    const driver = new S3Driver(minioConfig(),client);
    try {
      expect((await driver.read(key,bytes.length,'abcd')).equals(bytes)).toBe(true);
      expect((send.mock.calls[0]![0] as GetObjectCommand).input).toMatchObject({Key:key,IfMatch:'abcd'});
      send.mockRejectedValueOnce(new Error('fictional-private-sdk') as never).mockResolvedValueOnce({} as never);
      for (let i=0;i<2;i++) await expect(driver.read(key,bytes.length,'abcd')).rejects.toMatchObject({code:'UNAVAILABLE'});
      await expect(driver.read(key,MAX_READ_BYTES+1,'abcd')).rejects.toMatchObject({code:'INVALID_INPUT'});
      expect(send).toHaveBeenCalledTimes(3);
    } finally { driver.close(); }
  });
  it('原生 OSS 有相同 If-Match 与有界流契约，不冒充真实 OSS 验证', async (): Promise<void> => {
    const config = ossConfig(); const client = new OSS({...config,secure:true,authorizationV4:true});
    const get = jest.spyOn(client,'getStream').mockResolvedValueOnce({stream:Readable.from([bytes])} as OSS.GetStreamResult);
    const driver = new OssDriver(config,client);
    expect((await driver.read(key,bytes.length,'abcd')).equals(bytes)).toBe(true);
    expect(get).toHaveBeenCalledWith(key,{headers:{'If-Match':'abcd'}});
    get.mockRejectedValueOnce(new Error('fictional-private-sdk')).mockResolvedValueOnce({} as OSS.GetStreamResult);
    for (let i=0;i<2;i++) await expect(driver.read(key,bytes.length,'abcd')).rejects.toMatchObject({code:'UNAVAILABLE'});
    await expect(driver.read(key,MAX_READ_BYTES+1,'abcd')).rejects.toMatchObject({code:'INVALID_INPUT'});
    expect(get).toHaveBeenCalledTimes(3);
  });
});
