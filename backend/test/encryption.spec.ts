import { randomBytes } from 'node:crypto';
import { EncryptionService } from '../src/encryption.service';

describe('敏感字段 AES-256-GCM', (): void => {
  const key = randomBytes(32);
  const cipher = new EncryptionService(key);
  const context = 'CaseParty:fictional-uuid:idCard';
  const input = 'FICTIONAL-ID-CARD（虚构证件）';

  it('加解密可还原 Unicode，密文不包含原文', (): void => {
    const encrypted = cipher.encrypt(input, context);
    expect(cipher.decrypt(encrypted, context)).toBe(input);
    expect(Buffer.from(encrypted).includes(Buffer.from(input))).toBe(false);
    expect(Buffer.from(encrypted).subarray(0, 4).toString()).toBe('GCM1');
  });
  it('同一输入每次生成不同随机 nonce 和密文', (): void => {
    const a = cipher.encrypt(input, context);
    const b = cipher.encrypt(input, context);
    expect(a).not.toEqual(b);
    expect(cipher.decrypt(a, context)).toBe(cipher.decrypt(b, context));
  });
  it('篡改密文不得解密', (): void => {
    const encrypted = cipher.encrypt(input, context);
    encrypted[encrypted.length - 1] = encrypted[encrypted.length - 1]! ^ 1;
    expect((): void => { cipher.decrypt(encrypted, context); }).toThrow('敏感字段解密失败');
  });
  it('不同记录或字段上下文不得解密', (): void => {
    expect((): void => { cipher.decrypt(cipher.encrypt(input, context), 'CaseParty:other-uuid:phone'); })
      .toThrow('敏感字段解密失败');
  });
  it('错误密钥不得解密且错误不泄露输入', (): void => {
    const other = new EncryptionService(randomBytes(32));
    expect((): void => { other.decrypt(cipher.encrypt(input, context), context); })
      .toThrow(new Error('敏感字段解密失败'));
  });
  it.each([new Uint8Array(), new Uint8Array(64)])('拒绝空密文或未知格式', (value: Uint8Array): void => {
    expect((): void => { cipher.decrypt(value, context); }).toThrow('敏感字段解密失败');
  });
});

describe('密钥隔离与盲索引', (): void => {
  const key = randomBytes(32);
  const cipher = new EncryptionService(key);
  const context = 'CaseParty:fictional-uuid:idCard';
  const input = 'FICTIONAL-ID-CARD（虚构证件）';

  it('不接受无效主密钥', (): void => {
    expect((): void => { new EncryptionService(randomBytes(31)); }).toThrow('加密密钥必须为 32 字节');
  });
  it('复制传入密钥，调用者修改原数组不破坏服务', (): void => {
    const mutableKey = randomBytes(32);
    const isolated = new EncryptionService(mutableKey);
    const encrypted = isolated.encrypt(input, context);
    mutableKey.fill(0);
    expect(isolated.decrypt(encrypted, context)).toBe(input);
  });
  it.each(['', ' '.repeat(3), 'x'.repeat(513), 'field\0other'])('拒绝无效上下文', (purpose: string): void => {
    expect((): void => { cipher.encrypt(input, purpose); }).toThrow('上下文');
    expect((): void => { cipher.blindIndex(input, purpose); }).toThrow('上下文');
    expect((): void => { cipher.decrypt(cipher.encrypt(input, context), purpose); }).toThrow('解密失败');
  });
  it('拒绝空敏感字段值', (): void => {
    expect((): void => { cipher.encrypt('', context); }).toThrow('不能为空');
    expect((): void => { cipher.blindIndex('', context); }).toThrow('不能为空');
  });
  it('盲索引可稳定查找且隔离值、用途和密钥', (): void => {
    const a = cipher.blindIndex('FICTIONAL-PHONE', 'User.phone');
    expect(a.byteLength).toBe(32);
    expect(a).toEqual(cipher.blindIndex('FICTIONAL-PHONE', 'User.phone'));
    expect(a).not.toEqual(cipher.blindIndex('FICTIONAL-OTHER', 'User.phone'));
    expect(a).not.toEqual(cipher.blindIndex('FICTIONAL-PHONE', 'Other.phone'));
    expect(a).not.toEqual(new EncryptionService(randomBytes(32)).blindIndex('FICTIONAL-PHONE', 'User.phone'));
  });
});
