import { ForbiddenException } from '@nestjs/common';
import { DocumentUpload } from '@prisma/client';
import { createHash } from 'node:crypto';
import { dto } from '../src/modules/case/case-input';
import { PresignInput, RegisterInput, VisibilityInput } from '../src/modules/document/document-input';
import { checkQuota, storageOperation, verifyObject } from '../src/modules/document/document-policy';
import { StorageError } from '../src/modules/document/storage/storage-error';

describe('文件业务单元：输入、配额与真实元数据策略', (): void => {
  const contentMd5 = createHash('md5').update('fictional').digest('base64');
  const ticket = { sizeBytes: 9n, mimeType: 'application/pdf', contentMd5 } as DocumentUpload;
  const valid = { sizeBytes: 9, mimeType: 'application/pdf', etag: Buffer.from(contentMd5, 'base64').toString('hex') };

  it.each([null, { ...valid, sizeBytes: 8 }, { ...valid, mimeType: 'text/html' }, { ...valid, etag: 'abc' }])(
    '对象缺失或大小、类型、协议摘要不匹配时拒绝登记 %#', (object): void => {
      expect((): void => verifyObject(ticket, object)).toThrow('上传内容尚未就绪');
    });
  it('接受带引号/大写的等价协议摘要；不把校验值当身份认证', (): void => {
    expect((): void => verifyObject(ticket, { ...valid, etag: `"${valid.etag.toUpperCase()}"` })).not.toThrow();
  });
  it('BigInt 容量边界不丢精度；降级后超过配额也拒绝增长', (): void => {
    const quota = 9007199254740993n;
    expect((): void => checkQuota(quota - 1n, 1n, quota)).not.toThrow();
    expect((): void => checkQuota(quota, 1n, quota)).toThrow('配额不足');
    expect((): void => checkQuota(quota + 1n, 1n, quota)).toThrow('配额不足');
  });
  it('仅转换存储错误，保留业务权限状态；未知错误不泄露供应商内容', async (): Promise<void> => {
    await expect(storageOperation(async (): Promise<never> => { throw new StorageError('INVALID_INPUT'); })).rejects.toMatchObject({ status: 400 });
    await expect(storageOperation(async (): Promise<never> => { throw new Error('fictional-private-provider-detail'); }))
      .rejects.toMatchObject({ status: 503, message: '文件存储暂不可用，请稍后重试' });
    const forbidden = new ForbiddenException();
    await expect(storageOperation(async (): Promise<never> => { throw forbidden; })).rejects.toBe(forbidden);
  });
  it.each([{ previousDocumentId: null }, { sizeBytes: '9' }, { sizeBytes: 1.1 }, { contentMd5: 'invalid' }])(
    '上传 DTO 拒绝错误类型和空版本标识 %#', (change): void => {
      expect((): unknown => dto(PresignInput, { fileName: 'fake.pdf', mimeType: 'application/pdf', sizeBytes: 9, contentMd5, ...change })).toThrow();
    });
  it('登记必须提供分类；可见性只能是布尔值且不能夹带其他字段', (): void => {
    expect((): unknown => dto(RegisterInput, { uploadId: 'invalid' })).toThrow();
    expect((): unknown => dto(VisibilityInput, { isClientVisible: true, ownerId: 'fake' })).toThrow();
    expect(dto(VisibilityInput, { isClientVisible: false }).isClientVisible).toBe(false);
  });
});
