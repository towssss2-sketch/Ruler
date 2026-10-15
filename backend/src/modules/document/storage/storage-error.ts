export type StorageErrorCode = 'INVALID_INPUT' | 'UNAVAILABLE' | 'NOT_FOUND';
const MESSAGES: Record<StorageErrorCode, string> = {
  INVALID_INPUT: '文件存储参数无效', UNAVAILABLE: '文件存储暂不可用', NOT_FOUND: '文件对象不存在',
};

/** 不附带底层异常、请求路径、连接串或签名，避免 SDK 错误泄露凭据。 */
export class StorageError extends Error {
  constructor(readonly code: StorageErrorCode) { super(MESSAGES[code]); this.name = 'StorageError'; }
}

/** 只读取 SDK 固定错误码，不序列化或记录整个错误对象。 */
export function storageErrorCode(error: unknown): string | undefined {
  if (!error || typeof error !== 'object') return undefined;
  const record = error as Record<string, unknown>;
  const code = record.code ?? record.name;
  return typeof code === 'string' ? code : undefined;
}
