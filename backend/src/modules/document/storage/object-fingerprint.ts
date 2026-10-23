import { createHash } from 'node:crypto';
import { Readable } from 'node:stream';
import { StorageError } from './storage-error';
import { MAX_FILE_BYTES, validateKey } from './storage-policy';

/** 指纹读取绑定规范键、精确长度和 ETag，不接受任意网络地址。 */
export function validateFingerprint(key: string, size: number, etag: string): void {
  validateKey(key);
  if (!Number.isSafeInteger(size) || size < 1 || size > MAX_FILE_BYTES || !/^"?[a-fA-F0-9]+"?$/.test(etag)) {
    throw new StorageError('INVALID_INPUT');
  }
}

/** 流式读取实际对象算 SHA-256；有界长度/时间，失败和完成均销毁本次流。 */
export async function hashObjectStream(source: unknown, expected: number): Promise<string> {
  if (!(source instanceof Readable)) throw new StorageError('UNAVAILABLE');
  const timer = setTimeout((): void => { source.destroy(new StorageError('UNAVAILABLE')); }, 30000);
  timer.unref();
  try {
    const hash = createHash('sha256'); let length = 0;
    for await (const raw of source) {
      const chunk: unknown = raw;
      if (!(chunk instanceof Uint8Array)) throw new StorageError('UNAVAILABLE');
      length += chunk.byteLength;
      if (length > expected) throw new StorageError('UNAVAILABLE');
      hash.update(chunk);
    }
    if (length !== expected) throw new StorageError('UNAVAILABLE');
    return hash.digest('hex');
  } catch { throw new StorageError('UNAVAILABLE'); }
  finally { clearTimeout(timer); source.destroy(); }
}
