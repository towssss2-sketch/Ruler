import { Injectable } from '@nestjs/common';
import { fork } from 'node:child_process';
import { resolve } from 'node:path';
import { MAX_READ_BYTES } from '../../document/storage/object-reader';
import { ExtractionKind, ExtractionResult, manualResult, MAX_TEXT_LENGTH } from './extraction-result';

/** 资源受限的解析子进程；不继承数据库、对象存储、字段密钥等运行环境。 */
@Injectable()
export class DocumentTextExtractor {
  /** 至多 15 秒解析，128MiB V8 堆；失败返回固定原因，调用者保留原件供人工处理。 */
  async extract(bytes: Buffer, kind: ExtractionKind): Promise<ExtractionResult> {
    if (bytes.length > MAX_READ_BYTES) return manualResult('FILE_TOO_LARGE');
    const worker = resolve(__dirname, '../../../../dist/modules/ingestion/extraction/document-text-worker.js');
    return new Promise<ExtractionResult>((resolveResult): void => {
      const child = fork(worker, [kind, String(bytes.length)], { env: {},
        execArgv: ['--max-old-space-size=128'], stdio: ['pipe', 'ignore', 'ignore', 'ipc'] });
      let settled = false;
      const finish = (result: ExtractionResult): void => {
        if (settled) return;
        settled = true; clearTimeout(timer); child.kill('SIGKILL'); resolveResult(result);
      };
      const timer = setTimeout((): void => finish(manualResult('TIMEOUT')), 15000);
      child.once('error', (): void => finish(manualResult('UNAVAILABLE')));
      child.once('exit', (): void => finish(manualResult('UNAVAILABLE')));
      child.once('message', (message: unknown): void => finish(workerResult(message)));
      child.stdin?.on('error', (): void => finish(manualResult('UNAVAILABLE')));
      child.stdin?.end(bytes);
    }).catch((): ExtractionResult => manualResult('UNAVAILABLE'));
  }
}

/** IPC 边界只接受规范结果；不透传未知错误或异常大正文。 */
export function workerResult(message: unknown): ExtractionResult {
  if (!message || typeof message !== 'object') return manualResult('UNAVAILABLE');
  const value = message as Record<string, unknown>;
  if (value.state === 'TEXT' && typeof value.text === 'string' && value.text.length > 0 && value.text.length <= MAX_TEXT_LENGTH) {
    return { state: 'TEXT', text: value.text };
  }
  if (value.state === 'MANUAL_REQUIRED' && ['INVALID_DOCUMENT', 'CONTENT_LIMIT', 'NO_TEXT', 'UNSUPPORTED_CONTENT'].includes(String(value.reason))) {
    return manualResult(value.reason as 'INVALID_DOCUMENT' | 'CONTENT_LIMIT' | 'NO_TEXT' | 'UNSUPPORTED_CONTENT');
  }
  return manualResult('UNAVAILABLE');
}
