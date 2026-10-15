import { randomUUID } from 'node:crypto';
import { MAX_FILE_BYTES, downloadDisposition, objectMetadata, sanitizeFileName, storageKey, uploadHeaders,
  validateCopy, validateKey, validateTtl } from '../src/modules/document/storage/storage-policy';
import { storageErrorCode } from '../src/modules/document/storage/storage-error';
import { uploadInput } from './storage/fixtures';

describe('存储路径与文件名边界', (): void => {
  it('规范化特殊字符、保留中文扩展名，生成固定四段路径', (): void => {
    expect(sanitizeFileName(' 虚构<script>.pdf ')).toBe('虚构_script_.pdf');
    expect(sanitizeFileName('..虚构..pdf')).toBe('虚构_pdf');
    const key = storageKey(randomUUID(), randomUUID(), randomUUID(), 2, '虚构材料.pdf');
    expect(key.split('/')).toHaveLength(4);
    expect((): void => validateKey(key)).not.toThrow();
    expect(downloadDisposition(key).includes("filename*=UTF-8''")).toBe(true);
    expect(downloadDisposition(key).includes('\r')).toBe(false);
  });
  it.each(['../secret.pdf', 'a/b.pdf', 'a\\b.pdf', '\u0000.pdf', 'a\r\n.pdf', '..', '', '汉'.repeat(100)+'.pdf', 'a'.repeat(513)])(
    '拒绝穿越、控制字符、空名和超长文件名 #%#', (name: string): void => {
      expect((): string => sanitizeFileName(name)).toThrow('文件存储参数无效');
    });
  it('驱动不接受编码分隔符、未清理文件名、非法 UUID 或版本', (): void => {
    const key = uploadInput().key;
    for (const value of ['../x', key.replace('/1_', '/0_'), key.replace('材料', '%2F'), key.replace('材料', '<x>')]) {
      expect((): void => validateKey(value)).toThrow();
    }
    expect((): string => storageKey('bad', randomUUID(), randomUUID(), 1, 'a.pdf')).toThrow();
    expect((): string => storageKey(randomUUID(), randomUUID(), randomUUID(), 2147483648, 'a.pdf')).toThrow();
    expect((): void => validateKey(`${randomUUID()}/${randomUUID()}/${randomUUID()}/1.5_a.pdf`)).toThrow();
  });
});

describe('上传大小、类型与签名边界', (): void => {
  it.each([0, -1, 1.5, Number.NaN, MAX_FILE_BYTES+1])('拒绝非法文件大小 #%#', (sizeBytes: number): void => {
    expect((): unknown => uploadHeaders({ ...uploadInput(), sizeBytes })).toThrow();
  });
  it('接受 200 MiB 边界和全部允许类型，拒绝 MIME 原型键和扩展名不匹配', (): void => {
    expect(uploadHeaders({ ...uploadInput(), sizeBytes: MAX_FILE_BYTES })['content-length']).toBe(String(MAX_FILE_BYTES));
    for (const [mimeType, extension] of [['application/pdf', 'pdf'], ['application/msword', 'doc'],
      ['application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx'], ['image/jpeg', 'jpg'],
      ['image/png', 'png'], ['video/mp4', 'mp4']]) {
      expect(uploadHeaders({ ...uploadInput(`虚构.${extension}`), mimeType: mimeType! })['content-type']).toBe(mimeType);
    }
    for (const mimeType of ['text/html', '__proto__', 'constructor', 'image/png']) {
      expect((): unknown => uploadHeaders({ ...uploadInput(), mimeType })).toThrow('文件存储参数无效');
    }
  });
  it.each(['', 'not-base64', 'AAAAAAAAAAAAAAAAAAAAAB=='])('拒绝非规范内容校验值 #%#', (contentMd5: string): void => {
    expect((): unknown => uploadHeaders({ ...uploadInput(), contentMd5 })).toThrow();
  });
  it.each([0, 601, -1, 1.2, Number.NaN])('拒绝无效或超过十分钟的有效期 #%#', (ttl: number): void => {
    expect((): void => validateTtl(ttl)).toThrow();
  });
  it('有效期支持一秒与十分钟，复制拒绝同键与头注入', (): void => {
    expect((): void => validateTtl(1)).not.toThrow();
    expect((): void => validateTtl(600)).not.toThrow();
    const key = uploadInput().key;
    expect((): void => validateCopy(key, key)).toThrow();
    expect((): void => validateCopy(key, uploadInput().key, 'a\r\nheader:bad')).toThrow();
  });
});

describe('供应商元数据和错误边界', (): void => {
  it('读取实际元数据，拒绝无法用于配额判断的长度或缺失类型', (): void => {
    expect(objectMetadata('20', 'application/pdf', '"abcdef"')).toEqual({ sizeBytes: 20, mimeType: 'application/pdf', etag: '"abcdef"' });
    for (const size of ['NaN', -1, undefined, 1.5, Number.MAX_SAFE_INTEGER+1]) {
      expect((): unknown => objectMetadata(size, 'application/pdf', 'abcdef')).toThrow('文件存储暂不可用');
    }
    expect((): unknown => objectMetadata(1, undefined, 'abcdef')).toThrow();
    expect((): unknown => objectMetadata(1, 'application/pdf', undefined)).toThrow();
  });
  it('只提取固定供应商错误码，不读取或输出完整错误', (): void => {
    expect(storageErrorCode(null)).toBeUndefined();
    expect(storageErrorCode('secret')).toBeUndefined();
    expect(storageErrorCode({ code: 404 })).toBeUndefined();
    expect(storageErrorCode({ code: 'NoSuchKey', signedUrl: 'fictional-secret' })).toBe('NoSuchKey');
    expect(storageErrorCode({ name: 'NotFound' })).toBe('NotFound');
  });
});
