import { z } from 'zod';
import { StorageError } from './storage-error';
import { StoredObject, UploadRequest } from './storage.service';

export const MAX_FILE_BYTES = 200 * 1024 * 1024;
export const MIME_EXTENSIONS: Readonly<Record<string, readonly string[]>> = {
  'application/pdf': ['pdf'], 'application/msword': ['doc'],
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': ['docx'],
  'image/jpeg': ['jpg', 'jpeg'], 'image/png': ['png'], 'video/mp4': ['mp4'],
};
const uuid = z.string().uuid();
const safeName = /^[\p{L}\p{N}][\p{L}\p{N}_.-]*$/u;

/** 清理文件名，保留扩展名并限制 UTF-8 字节数；不接受路径或控制字符。 */
export function sanitizeFileName(input: string): string {
  if (typeof input !== 'string' || input.length > 512 || /[/\\]/.test(input)
    || [...input].some((char): boolean => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127)) throw new StorageError('INVALID_INPUT');
  const normalized = input.normalize('NFKC').trim().replace(/[^\p{L}\p{N}_.-]/gu, '_')
    .replace(/\.{2,}/g, '_').replace(/^[._-]+/, '');
  if (!safeName.test(normalized) || Buffer.byteLength(normalized, 'utf8') > 200) throw new StorageError('INVALID_INPUT');
  return normalized;
}

/** 生成原需求指定的所有者/案件/文档/版本_文件名结构，不接收任意前缀。 */
export function storageKey(ownerId: string, caseId: string, documentId: string, version: number, fileName: string): string {
  if (![ownerId, caseId, documentId].every((id): boolean => uuid.safeParse(id).success)
    || !Number.isSafeInteger(version) || version < 1 || version > 2147483647) throw new StorageError('INVALID_INPUT');
  return `${ownerId}/${caseId}/${documentId}/${version}_${sanitizeFileName(fileName)}`;
}

/** 驱动边界再次拒绝路径穿越、编码分隔符及非规范键，避免绕过上层构造器。 */
export function validateKey(key: string): void {
  if (typeof key !== 'string') throw new StorageError('INVALID_INPUT');
  const parts = key.split('/');
  if (parts.length === 5 && parts[1] === 'ingestion') {
    if (ingestionStorageKey(parts[0]!, parts[2]!, parts[3]!, parts[4]!.replace(/^1_/, '')) !== key) {
      throw new StorageError('INVALID_INPUT');
    }
    return;
  }
  if (parts.length !== 4) throw new StorageError('INVALID_INPUT');
  const match = /^([1-9]\d*)_(.+)$/.exec(parts[3]!);
  if (!match || storageKey(parts[0]!, parts[1]!, parts[2]!, Number(match[1]), match[2]!) !== key) {
    throw new StorageError('INVALID_INPUT');
  }
}

/** 未选案件时使用独立的用户/归集命名空间，不伪造案件 UUID。 */
export function ingestionStorageKey(userId: string, batchId: string, objectId: string, fileName: string): string {
  if (![userId, batchId, objectId].every((id): boolean => uuid.safeParse(id).success)) throw new StorageError('INVALID_INPUT');
  return `${userId}/ingestion/${batchId}/${objectId}/1_${sanitizeFileName(fileName)}`;
}

/** 上传只允许指定六类 MIME，长度至多 200 MiB，校验值必须是规范 Base64 MD5。 */
export function uploadHeaders(input: UploadRequest): Record<string, string> {
  validateKey(input.key);
  const extension = input.key.split('.').at(-1)!.toLowerCase();
  const extensions = Object.hasOwn(MIME_EXTENSIONS, input.mimeType) ? MIME_EXTENSIONS[input.mimeType] : undefined;
  if (!extensions?.includes(extension) || !Number.isSafeInteger(input.sizeBytes)
    || input.sizeBytes < 1 || input.sizeBytes > MAX_FILE_BYTES
    || typeof input.contentMd5 !== 'string' || !/^[A-Za-z0-9+/]{22}==$/.test(input.contentMd5)
    || Buffer.from(input.contentMd5, 'base64').toString('base64') !== input.contentMd5) throw new StorageError('INVALID_INPUT');
  return { 'content-type': input.mimeType, 'content-length': String(input.sizeBytes), 'content-md5': input.contentMd5 };
}

/** 下载强制附件并禁止共享缓存；名称经规范化后按 RFC 5987 编码。 */
export function downloadDisposition(key: string): string {
  validateKey(key);
  const name = key.split('/').at(-1)!.replace(/^\d+_/, '');
  return `attachment; filename="download"; filename*=UTF-8''${encodeURIComponent(name)}`;
}

/** 双驱动均在调用 SDK 前检查有效期，绝不自动放宽到十分钟以上。 */
export function validateTtl(seconds: number): void {
  if (!Number.isInteger(seconds) || seconds < 1 || seconds > 600) throw new StorageError('INVALID_INPUT');
}

/** 对象存储返回值也必须验证；损坏或缺失元数据不能用于配额计算。 */
export function objectMetadata(size: unknown, mimeType: unknown, etag: unknown): StoredObject {
  const value = typeof size === 'string' && /^\d+$/.test(size) ? Number(size) : size;
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0 || typeof mimeType !== 'string'
    || mimeType.length === 0 || typeof etag !== 'string' || !/^"?[a-fA-F0-9]+(?:-\d+)?"?$/.test(etag)) {
    throw new StorageError('UNAVAILABLE');
  }
  return { sizeBytes: value, mimeType, etag };
}

/** ETag 作为复制条件时拒绝换行或额外头内容。 */
export function validateCopy(sourceKey: string, targetKey: string, etag?: string): void {
  validateKey(sourceKey); validateKey(targetKey);
  if (sourceKey === targetKey || (etag !== undefined && !/^"?[a-fA-F0-9]+(?:-\d+)?"?$/.test(etag))) {
    throw new StorageError('INVALID_INPUT');
  }
}
