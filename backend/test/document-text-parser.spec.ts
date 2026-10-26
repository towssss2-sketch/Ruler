jest.mock('pdf-parse', (): object => ({ PDFParse: jest.fn() }));
jest.mock('mammoth', (): object => ({ extractRawText: jest.fn() }));
import { PDFParse } from 'pdf-parse';
import mammoth from 'mammoth';
import { parseDocument } from '../src/modules/ingestion/extraction/document-text-parser';
import { fictionalDocx } from './ingestion/text-fixtures';

afterEach((): void => { jest.resetAllMocks(); });
describe('解析器错误分支与清理契约（真实解析另由子进程测试验证）', (): void => {
  it('PDF 完整读出、不跟随超链接、禁用 eval，成功与异常均销毁解析器', async (): Promise<void> => {
    const destroy = jest.fn().mockResolvedValue(undefined);
    const getText = jest.fn().mockResolvedValue({text:'虚构正文'});
    (PDFParse as unknown as jest.Mock).mockImplementation((): object => ({getInfo:jest.fn().mockResolvedValue({total:1}),getText,destroy}));
    expect(await parseDocument(Buffer.from('%PDF-1.7'),'pdf')).toEqual({state:'TEXT',text:'虚构正文'});
    expect(PDFParse).toHaveBeenCalledWith(expect.objectContaining({isEvalSupported:false,disableFontFace:true,stopAtErrors:true}));
    expect(getText).toHaveBeenCalledWith({parseHyperlinks:false,pageJoiner:''}); expect(destroy).toHaveBeenCalledTimes(1);
    getText.mockRejectedValueOnce(new Error('fictional-private-parser'));
    expect(await parseDocument(Buffer.from('%PDF-1.7'),'pdf')).toMatchObject({reason:'INVALID_DOCUMENT'});
    expect(destroy).toHaveBeenCalledTimes(2);
  });
  it('页数先检查，过多页不进入正文解析；坏文件头直接拒绝', async (): Promise<void> => {
    const getText = jest.fn(); const destroy = jest.fn().mockResolvedValue(undefined);
    (PDFParse as unknown as jest.Mock).mockImplementation((): object => ({getInfo:jest.fn().mockResolvedValue({total:101}),getText,destroy}));
    expect(await parseDocument(Buffer.from('%PDF-1.7'),'pdf')).toMatchObject({reason:'CONTENT_LIMIT'});
    expect(getText).not.toHaveBeenCalled(); expect(destroy).toHaveBeenCalledTimes(1);
    expect(await parseDocument(Buffer.from('fake'),'pdf')).toMatchObject({reason:'INVALID_DOCUMENT'});
    expect(await parseDocument(Buffer.from('fake'),'docx')).toMatchObject({reason:'INVALID_DOCUMENT'});
  });
  it('DOCX 只向纯文本 API 传内存；警告不透传，解析错误不返回部分结果', async (): Promise<void> => {
    const bytes = fictionalDocx('虚构正文');
    const extract = mammoth.extractRawText as jest.Mock;
    extract.mockResolvedValueOnce({value:'虚构正文',messages:[]});
    expect(await parseDocument(bytes,'docx')).toEqual({state:'TEXT',text:'虚构正文'});
    expect(extract).toHaveBeenCalledWith({buffer:bytes});
    extract.mockResolvedValueOnce({value:'partial',messages:[{type:'warning',message:'private-warning'}]});
    expect(await parseDocument(bytes,'docx')).toMatchObject({reason:'UNSUPPORTED_CONTENT'});
    extract.mockResolvedValueOnce({value:'partial private text',messages:[{type:'error',message:'private-error'}]});
    expect(await parseDocument(bytes,'docx')).toMatchObject({reason:'INVALID_DOCUMENT'});
    expect(await parseDocument(Buffer.from([0x50,0x4b,0x03,0x04]),'docx')).toMatchObject({reason:'INVALID_DOCUMENT'});
    extract.mockRejectedValueOnce(new Error('private-error'));
    expect(await parseDocument(bytes,'docx')).toMatchObject({reason:'INVALID_DOCUMENT'});
  });
});
