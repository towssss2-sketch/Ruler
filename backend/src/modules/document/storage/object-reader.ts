import { Readable } from 'node:stream';
import { StorageError } from './storage-error';
import { validateFingerprint } from './object-fingerprint';

export const MAX_READ_BYTES = 10 * 1024 * 1024;

/** 正文预览只读取至多 10MiB，不能沿用上传的 200MiB 上限分配内存。 */
export function validateRead(key: string, size: number, etag: string): void {
  validateFingerprint(key, size, etag);
  if (size > MAX_READ_BYTES) throw new StorageError('INVALID_INPUT');
}

/** 精确长度的有界读取；完成、超时和错误均释放对象流，不输出底层消息。 */
export async function readObjectStream(source: unknown, expected: number): Promise<Buffer> {
  if (!(source instanceof Readable)) throw new StorageError('UNAVAILABLE');
  const timer = setTimeout((): void => { source.destroy(new StorageError('UNAVAILABLE')); }, 10000);
  timer.unref();
  try {
    if (!Number.isSafeInteger(expected) || expected < 1 || expected > MAX_READ_BYTES) throw new Error();
    const chunks: Buffer[] = []; let length = 0;
    for await (const raw of source) {
      const chunk: unknown = raw;
      if (!(chunk instanceof Uint8Array)) throw new Error();
      length += chunk.byteLength;
      if (length > expected) throw new Error();
      chunks.push(Buffer.from(chunk));
    }
    if (length !== expected) throw new Error();
    return Buffer.concat(chunks, length);
  } catch { throw new StorageError('UNAVAILABLE'); }
  finally { clearTimeout(timer); source.destroy(); }
}
