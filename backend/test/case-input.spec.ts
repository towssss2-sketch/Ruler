import { randomUUID } from 'node:crypto';
import { CaseQuery, caseInput, dto } from '../src/modules/case/case-input';
import { input } from './case/fixture';

describe('案件 DTO 严格边界', (): void => {
  it.each([{}, [], null, 'text', { ownerId: randomUUID() }, { caseNo: 'bad' }, { caseNo: null },
    { parties: [] }, { parties: null }, { fee: 0.1 }, { fee: '-1' }, { fee: '100.001' }, { fee: 'NaN' },
    { cause: '  ' }, { status: 'DELETED' }, { status: null }, { notes: 'a'.repeat(10001) },
    { parties: [{ role: 'OWNER', name: '虚构甲' }] }, { parties: [{ role: 'PLAINTIFF', name: ' ' }] },
    { parties: [{ role: 'PLAINTIFF', name: '虚构甲', id: null }] }, { parties: Array.from({ length: 101 }, (): object => ({ role: 'PLAINTIFF', name: '虚构甲' })) },
  ])('拒绝非法修改输入 #%#', (value: unknown): void => {
    expect((): unknown => caseInput(value, false)).toThrow('Bad Request');
  });
  it('创建必须完整，禁止重复/自带当事人 id，拒绝未知字段与原型键', (): void => {
    expect((): unknown => caseInput({ cause: '虚构' }, true)).toThrow();
    const party = { id: randomUUID(), role: 'PLAINTIFF', name: '虚构甲' };
    expect((): unknown => caseInput({ ...input(), parties: [party] }, true)).toThrow();
    expect((): unknown => caseInput({ parties: [party, party] }, false)).toThrow();
    expect((): unknown => caseInput({ ...input(), extra: true }, true)).toThrow();
    expect((): unknown => caseInput(JSON.parse('{"__proto__":{}}') as unknown, false)).toThrow();
  });
  it('兼容全角括号与空格，允许显式清空，保留精确十进制金额', (): void => {
    expect(caseInput({ ...input(), caseNo: ' （2026） 浙0302民初16812号 ' }, true).caseNo).toBe('(2026)浙0302民初16812号');
    expect(caseInput({ fee: '0.01', notes: null, clerkPhone: null }, false)).toMatchObject({ fee: '0.01', notes: null });
  });
  it.each([{ page: '0' }, { page: '10000' }, { pageSize: '101' }, { page: ['1', '2'] },
    { sort: 'injection' }, { keyword: {} }, { keyword: '' }, { status: 'INVALID' }, { ownerId: randomUUID() }])(
    '拒绝无界/重复分页及未知查询 #%#', (value: unknown): void => { expect((): unknown => dto(CaseQuery, value)).toThrow(); });
});
