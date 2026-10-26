import { DocumentTextExtractor, workerResult } from '../src/modules/ingestion/extraction/document-text-extractor';
import { MAX_TEXT_LENGTH, textResult } from '../src/modules/ingestion/extraction/extraction-result';
import { suggestDocument } from '../src/modules/ingestion/extraction/document-rules';
import { fictionalDocx, fictionalPdf, testZip } from './ingestion/text-fixtures';

const extractor = new DocumentTextExtractor();
describe('真实 PDF/DOCX 解析子进程与保守标题规则', (): void => {
  it('真实 PDF 文本层与压缩 DOCX 中文段落可提取，原输入不被修改', async (): Promise<void> => {
    const pdf = fictionalPdf(); const original = Buffer.from(pdf);
    expect(await extractor.extract(pdf, 'pdf')).toEqual({ state: 'TEXT', text: 'Fictional test document' });
    expect(pdf.equals(original)).toBe(true);
    const docx = await extractor.extract(fictionalDocx('民事起诉状\n（2026）浙0302民初123号\n仅为虚构测试材料'), 'docx');
    expect(docx.state).toBe('TEXT');
    if (docx.state !== 'TEXT') throw new Error('未得到虚构 DOCX 正文');
    expect(docx.text).toContain('仅为虚构测试材料');
    expect(suggestDocument(docx.text)).toMatchObject({ category: 'PLEADING', caseNumbers: ['(2026)浙0302民初123号'], requiresConfirmation: true });
  });
  it('伪装 MIME、损坏文档、无正文 ZIP 不返回部分正文或异常信息', async (): Promise<void> => {
    for (const [bytes, kind] of [[Buffer.from('fictional-private-parser-error'), 'pdf'],
      [Buffer.from('%PDF-1.7\nprivate broken'), 'pdf'], [Buffer.from('not zip'), 'docx'],
      [testZip({ 'fictional.txt': 'private content' }), 'docx']] as const) {
      expect(await extractor.extract(bytes, kind)).toEqual({ state: 'MANUAL_REQUIRED', reason: 'INVALID_DOCUMENT', retryable: false });
    }
  });
  it('无文本层和空 DOCX 要求人工处理，页数/正文长度/文件大小超限不截断冒充成功', async (): Promise<void> => {
    for (const [bytes, kind] of [[fictionalPdf(''), 'pdf'], [fictionalDocx(''), 'docx']] as const) {
      expect(await extractor.extract(bytes, kind)).toMatchObject({ reason: 'NO_TEXT', retryable: false });
    }
    expect(await extractor.extract(fictionalPdf('fictional', 101), 'pdf')).toMatchObject({ reason: 'CONTENT_LIMIT' });
    expect(await extractor.extract(fictionalDocx('甲'.repeat(MAX_TEXT_LENGTH + 1)), 'docx')).toMatchObject({ reason: 'CONTENT_LIMIT' });
    expect(await extractor.extract(Buffer.alloc(10 * 1024 * 1024 + 1), 'pdf')).toMatchObject({ reason: 'FILE_TOO_LARGE' });
  });
  it('只接受独立明确标题，全部既有类别保留，冲突和引用不自动选择', (): void => {
    const titles = ['民事起诉状','答辩状','证据目录','开庭传票','授权委托书','庭审笔录','代理词','民事判决书','民事裁定书','法律服务合同'];
    const categories = ['PLEADING','DEFENSE','EVIDENCE','SUMMONS','AUTHORIZATION','HEARING_RECORD','REPRESENTATION','JUDGMENT','COURT_DOCUMENT','SERVICE_CONTRACT'];
    titles.forEach((title,index): void => { expect(suggestDocument(title).category).toBe(categories[index]); });
    expect(suggestDocument('虚构法院\n民 事 起 诉 状\n正文').category).toBe('PLEADING');
    expect(suggestDocument('民事起诉状\n民事判决书')).toMatchObject({ category: null, reason:'CONFLICTING_TITLES' });
    for (const text of ['本合同提及民事起诉状，不是起诉状', '其他材料', 'constructor', 'toString', '服务合同.pdf']) {
      expect(suggestDocument(text)).toMatchObject({ category: null, reason: 'NO_TITLE' });
    }
    expect(suggestDocument(`${'非标题正文\n'.repeat(12)}民事起诉状`).category).toBeNull();
  });
  it('案号只给有界候选，不自动匹配案件、当事人或法律日期', (): void => {
    const text = '（2026）浙0302民初123号\n(2026)浙0302民初123号\n2026-10-26';
    expect(suggestDocument(text)).toEqual({ ruleVersion:'title-v1', category:null, reason:'NO_TITLE',
      caseNumbers:['(2026)浙0302民初123号'], caseNumbersTruncated:false, requiresConfirmation:true });
    const many = suggestDocument(Array.from({length:11},(_,i): string => `(2026)浙民初${i}号`).join('\n'));
    expect(many.caseNumbers).toHaveLength(10); expect(many.caseNumbersTruncated).toBe(true);
  });
  it('IPC 非规范结果与过量输出拒绝；控制字符清理但不改变段落', (): void => {
    for (const result of [null, 'secret', {}, {state:'TEXT',text:''}, {state:'TEXT',text:'x'.repeat(MAX_TEXT_LENGTH+1)},
      {state:'MANUAL_REQUIRED',reason:'private-stack'}]) expect(workerResult(result)).toMatchObject({reason:'UNAVAILABLE'});
    expect(textResult('\0\r\n甲\r乙\n')).toEqual({ state:'TEXT',text:'甲\n乙' });
    expect(textResult(' '.repeat(MAX_TEXT_LENGTH+1))).toMatchObject({reason:'CONTENT_LIMIT'});
    expect(textResult(' \0 ')).toMatchObject({reason:'NO_TEXT'});
  });
});
