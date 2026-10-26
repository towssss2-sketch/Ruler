import { inflateRawSync } from 'node:zlib';

const MAX_EXPANDED_BYTES = 20 * 1024 * 1024;

/** 解包前核对中央目录和每个实际解压长度，拒绝加密/多卷/ZIP64 及超量包，防止小文件无限膨胀。 */
export function checkDocxLimits(bytes: Buffer): 'OK' | 'INVALID_DOCUMENT' | 'CONTENT_LIMIT' {
  try {
    const end = endOffset(bytes);
    const count = bytes.readUInt16LE(end + 10); const size = bytes.readUInt32LE(end + 12);
    let cursor = bytes.readUInt32LE(end + 16); let expanded = 0;
    if (count > 256 || size > MAX_EXPANDED_BYTES) return 'CONTENT_LIMIT';
    if (!count || bytes.readUInt16LE(end + 4) || bytes.readUInt16LE(end + 6) ||
      bytes.readUInt16LE(end + 8) !== count || cursor + size !== end) return 'INVALID_DOCUMENT';
    for (let entry = 0; entry < count; entry++) {
      if (cursor + 46 > end || bytes.readUInt32LE(cursor) !== 0x02014b50) return 'INVALID_DOCUMENT';
      const length = bytes.readUInt32LE(cursor + 24); expanded += length;
      if (expanded > MAX_EXPANDED_BYTES) return 'CONTENT_LIMIT';
      validateEntry(bytes, cursor, length);
      cursor += 46 + bytes.readUInt16LE(cursor + 28) + bytes.readUInt16LE(cursor + 30) + bytes.readUInt16LE(cursor + 32);
    }
    return cursor === end ? 'OK' : 'INVALID_DOCUMENT';
  } catch { return 'INVALID_DOCUMENT'; }
}

function endOffset(bytes: Buffer): number {
  for (let offset = bytes.length - 22; offset >= Math.max(0, bytes.length - 65557); offset--) {
    if (bytes.readUInt32LE(offset) === 0x06054b50 && offset + 22 + bytes.readUInt16LE(offset + 20) === bytes.length) return offset;
  }
  throw new Error();
}

function validateEntry(bytes: Buffer, cursor: number, length: number): void {
  const method = bytes.readUInt16LE(cursor + 10); const flags = bytes.readUInt16LE(cursor + 8);
  const compressed = bytes.readUInt32LE(cursor + 20); const local = bytes.readUInt32LE(cursor + 42);
  if (flags & 1 || ![0,8].includes(method) || bytes.readUInt16LE(cursor + 34) || local + 30 > cursor ||
    bytes.readUInt32LE(local) !== 0x04034b50 || bytes.readUInt16LE(local + 8) !== method) throw new Error();
  const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
  if (start + compressed > cursor) throw new Error();
  const raw = bytes.subarray(start, start + compressed);
  const actual = method === 8 ? inflateRawSync(raw, { maxOutputLength: Math.max(1, length) }) : raw;
  if (actual.length !== length) throw new Error();
}
