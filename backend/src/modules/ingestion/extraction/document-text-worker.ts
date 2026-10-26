import { readObjectStream, MAX_READ_BYTES } from '../../document/storage/object-reader';
import { parseDocument } from './document-text-parser';
import { manualResult } from './extraction-result';

/** 独立进程只从 stdin 接收字节、从 IPC 返回受限结果，日志流由父进程丢弃。 */
async function main(): Promise<void> {
  const kind = process.argv[2]; const size = Number(process.argv[3]);
  if ((kind !== 'pdf' && kind !== 'docx') || !Number.isSafeInteger(size) || size < 1 || size > MAX_READ_BYTES) {
    process.send?.(manualResult('INVALID_DOCUMENT')); return;
  }
  try { process.send?.(await parseDocument(await readObjectStream(process.stdin, size), kind)); }
  catch { process.send?.(manualResult('INVALID_DOCUMENT')); }
}

if (require.main === module) {
  void main().finally((): void => { process.disconnect?.(); });
}
