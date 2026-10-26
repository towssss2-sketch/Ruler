export const MAX_TEXT_LENGTH = 100000;
export const MAX_PDF_PAGES = 100;
export const DOCX_MIME = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
export type ExtractionKind = 'pdf' | 'docx';
export type ExtractionReason = 'UNSUPPORTED_FORMAT' | 'FILE_TOO_LARGE' | 'CONTENT_LIMIT' |
  'NO_TEXT' | 'INVALID_DOCUMENT' | 'UNSUPPORTED_CONTENT' | 'TIMEOUT' | 'UNAVAILABLE';
export type ExtractionResult = { state: 'TEXT'; text: string } |
  { state: 'MANUAL_REQUIRED'; reason: ExtractionReason; retryable: boolean };

/** 固定降级原因，不包含文件名、解析器异常或部分正文。 */
export function manualResult(reason: ExtractionReason): ExtractionResult {
  return { state: 'MANUAL_REQUIRED', reason, retryable: reason === 'TIMEOUT' || reason === 'UNAVAILABLE' };
}

/** 保留正文换行；超长整次降级，不用截断正文产生分类建议。 */
export function textResult(text: string): ExtractionResult {
  if (text.length > MAX_TEXT_LENGTH) return manualResult('CONTENT_LIMIT');
  const normalized = text.replace(/\r\n?/g, '\n').split('')
    .filter((char): boolean => char.charCodeAt(0) >= 32 || char === '\n' || char === '\t').join('').trim();
  return normalized ? { state: 'TEXT', text: normalized } : manualResult('NO_TEXT');
}
