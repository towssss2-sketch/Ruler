import { PDFParse } from 'pdf-parse';
import mammoth from 'mammoth';
import { ExtractionKind, ExtractionResult, manualResult, MAX_PDF_PAGES, textResult } from './extraction-result';
import { checkDocxLimits } from './docx-limits';

/** 只解析内存中的真实原件；无文件路径、HTML 转换、OCR 或外部链接抓取。 */
export async function parseDocument(bytes: Buffer, kind: ExtractionKind): Promise<ExtractionResult> {
  try {
    if (kind === 'pdf') return await parsePdf(bytes);
    if (!bytes.subarray(0, 4).equals(Buffer.from([0x50, 0x4b, 0x03, 0x04]))) return manualResult('INVALID_DOCUMENT');
    const checked = checkDocxLimits(bytes);
    if (checked !== 'OK') return manualResult(checked);
    const result = await mammoth.extractRawText({ buffer: bytes });
    // 解析器报告异常时不把部分识别当作完整正文，也不输出含内容的消息。
    if (result.messages.some((message): boolean => message.type === 'error')) return manualResult('INVALID_DOCUMENT');
    if (result.messages.length) return manualResult('UNSUPPORTED_CONTENT');
    return textResult(result.value);
  } catch { return manualResult('INVALID_DOCUMENT'); }
}

async function parsePdf(bytes: Buffer): Promise<ExtractionResult> {
  if (!bytes.subarray(0, 5).equals(Buffer.from('%PDF-'))) return manualResult('INVALID_DOCUMENT');
  const parser = new PDFParse({ data: Uint8Array.from(bytes), isEvalSupported: false,
    disableFontFace: true, useSystemFonts: false, stopAtErrors: true, verbosity: 0 });
  try {
    const info = await parser.getInfo();
    if (info.total > MAX_PDF_PAGES) return manualResult('CONTENT_LIMIT');
    const result = await parser.getText({ parseHyperlinks: false, pageJoiner: '' });
    return textResult(result.text);
  } finally { await parser.destroy(); }
}
