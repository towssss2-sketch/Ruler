import { checkDocxLimits } from '../src/modules/ingestion/extraction/docx-limits';
import { fictionalDocx, testZip } from './ingestion/text-fixtures';

describe('DOCX 解包资源边界', (): void => {
  it('真实压缩包和 ZIP 注释可检查，截断/伪造目录/多卷包拒绝', (): void => {
    const zip = fictionalDocx('虚构正文'); expect(checkDocxLimits(zip)).toBe('OK');
    const comment = Buffer.concat([zip,Buffer.from('fictional-comment')]); comment.writeUInt16LE(17,zip.length-2);
    expect(checkDocxLimits(comment)).toBe('OK');
    for (const size of [0,4,zip.length-1]) expect(checkDocxLimits(zip.subarray(0,size))).toBe('INVALID_DOCUMENT');
    for (const offset of [4,6,8,16]) {
      const bad = Buffer.from(zip); bad.writeUInt32LE(999,zip.length-22+offset);
      expect(checkDocxLimits(bad)).toBe('INVALID_DOCUMENT');
    }
  });
  it('条目数、总展开大小超限先拒绝，不能以小压缩包突破上限', (): void => {
    expect(checkDocxLimits(testZip(Object.fromEntries(Array.from({length:257},(_,i): [string,string] => [`${i}.txt`,'x']))))).toBe('CONTENT_LIMIT');
    const zip = fictionalDocx('虚构正文'); const central = zip.readUInt32LE(zip.length-6);
    const oversized = Buffer.from(zip); oversized.writeUInt32LE(20*1024*1024+1,central+24);
    expect(checkDocxLimits(oversized)).toBe('CONTENT_LIMIT');
    const directory = Buffer.from(zip); directory.writeUInt32LE(20*1024*1024+1,zip.length-10);
    expect(checkDocxLimits(directory)).toBe('CONTENT_LIMIT');
  });
  it('谎报展开长度、加密/未知算法/本地头/偏移/目录尾不一致全部拒绝', (): void => {
    const zip = testZip({'fictional.txt':'虚构'.repeat(100)}); const central = zip.readUInt32LE(zip.length-6);
    for (const [offset,value] of [[0,0],[8,1],[10,99],[20,0xffffffff],[24,1],[28,999],[34,1],[42,0xffffffff]] as const) {
      const bad = Buffer.from(zip); bad.writeUInt32LE(value,central+offset);
      expect(checkDocxLimits(bad)).toBe('INVALID_DOCUMENT');
    }
    for (const offset of [0,8]) {
      const bad = Buffer.from(zip); bad.writeUInt32LE(99,offset); expect(checkDocxLimits(bad)).toBe('INVALID_DOCUMENT');
    }
    const missing = Buffer.from(zip); missing.writeUInt16LE(0,zip.length-12);
    expect(checkDocxLimits(missing)).toBe('INVALID_DOCUMENT');
  });
});
