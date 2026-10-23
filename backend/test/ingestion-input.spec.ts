import { randomBytes } from 'node:crypto';
import { EncryptionService } from '../src/encryption.service';
import { emptyIngestionInput, textIngestionInput } from '../src/modules/ingestion/ingestion-input';
import { IngestionViewService } from '../src/modules/ingestion/ingestion-view.service';

describe('手动转发文字校验和用户域隔离', (): void => {
  it('只统一首尾空白和换行，保留正文空格、大小写及 Unicode', (): void => {
    expect(textIngestionInput({ rawContent: '  虚构 A  B\r\n第二行\r末行  ' }).rawContent).toBe('虚构 A  B\n第二行\n末行');
    expect(textIngestionInput({ rawContent: '字'.repeat(10000) }).rawContent).toHaveLength(10000);
  });
  it.each([null, [], {}, { rawContent: null }, { rawContent: 1 }, { rawContent: ' ' },
    { rawContent: '字'.repeat(10001) }, { rawContent: '坏\0文本' },
    { rawContent: '虚构', userId: 'fake' }, { rawContent: '虚构', attachments: [] },
    { rawContent: '虚构', channel: 'SMS' }, { rawContent: '虚构', matchedCaseId: 'fake' }])(
    '拒绝空白、超长、零字节或额外字段 %#', (value: unknown): void => {
      expect((): unknown => textIngestionInput(value)).toThrow();
    });
  it('忽略动作只接受空对象', (): void => {
    expect((): void => emptyIngestionInput({})).not.toThrow();
    for (const input of [null, [], '', { status: 'IGNORED' }, { userId: 'fake' }]) {
      expect((): void => emptyIngestionInput(input)).toThrow();
    }
  });
  it('内容哈希同用户稳定、跨用户和不同正文隔离，加密 AAD 拒绝错绑', (): void => {
    const cipher = new EncryptionService(randomBytes(32)); const service = new IngestionViewService(cipher);
    expect(service.hash('虚构', 'one')).toMatch(/^[a-f0-9]{64}$/);
    expect(service.hash('虚构', 'one')).toBe(service.hash('虚构', 'one'));
    expect(service.hash('虚构', 'one')).not.toBe(service.hash('虚构', 'two'));
    expect(service.hash('虚构', 'one')).not.toBe(service.hash('虚构二', 'one'));
    const encrypted = service.encrypt('虚构', 'one');
    expect(cipher.decrypt(encrypted, 'IngestionRecord:one:rawContent')).toBe('虚构');
    expect((): string => cipher.decrypt(encrypted, 'IngestionRecord:two:rawContent')).toThrow();
  });
});
