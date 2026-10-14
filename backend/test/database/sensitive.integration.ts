import { randomUUID } from 'node:crypto';
import { client, cipher, createCase, createUser } from './fixtures';

afterAll(async (): Promise<void> => { await client.$disconnect(); });

describe('指定敏感字段实际密文落库', (): void => {
  it('当事人证件/电话/地址以密文保存并可认证解密', async (): Promise<void> => {
    const caseRecord = await createCase(await createUser());
    const id = randomUUID();
    const fields = { idCard: 'FICTIONAL-ID', phone: 'FICTIONAL-PHONE', address: '虚构测试地址' };
    const party = await client.caseParty.create({ data: { id, caseId: caseRecord.id,
      role: 'PLAINTIFF', name: '虚构当事人',
      ...Object.fromEntries(Object.entries(fields).map(([name, value]): [string, Uint8Array<ArrayBuffer>] =>
        [name, cipher.encrypt(value, `CaseParty:${id}:${name}`)])) } });
    const stored = await client.caseParty.findUniqueOrThrow({ where: { id: party.id } });
    for (const [field, value] of Object.entries(fields)) {
      const encrypted = stored[field as keyof typeof fields]!;
      expect(Buffer.from(encrypted).includes(Buffer.from(value))).toBe(false);
      expect(cipher.decrypt(encrypted, `CaseParty:${id}:${field}`)).toBe(value);
    }
  });
  it.each(['idCard', 'phone', 'address'])('数据库拒绝 CaseParty.%s 明文误写', async (field: string): Promise<void> => {
    const caseRecord = await createCase(await createUser());
    await expect(client.caseParty.create({ data: { caseId: caseRecord.id, role: 'PLAINTIFF', name: '虚构当事人',
      [field]: new Uint8Array(Buffer.from('FICTIONAL-PLAINTEXT-SHOULD-BE-REJECTED')) } })).rejects.toThrow();
  });
  it('手机号盲索引独立于随机密文，重复手机号不能重复建用户', async (): Promise<void> => {
    const phone = `FICTIONAL-PHONE-${randomUUID()}`;
    const digest = cipher.blindIndex(phone, 'User.phone');
    const firstId = randomUUID();
    const first = await client.user.create({ data: { id: firstId, name: '虚构律师', passwordHash: 'TEST_ONLY_HASH',
      phone: cipher.encrypt(phone, `User:${firstId}:phone`), phoneLookupHash: digest } });
    const secondId = randomUUID();
    const secondCiphertext = cipher.encrypt(phone, `User:${secondId}:phone`);
    expect(secondCiphertext).not.toEqual(first.phone);
    await expect(client.user.create({ data: { id: secondId, name: '虚构律师', passwordHash: 'TEST_ONLY_HASH',
      phone: secondCiphertext, phoneLookupHash: digest } })).rejects.toMatchObject({ code: 'P2002' });
  });
  it('缺少手机号盲索引或写入明文手机号均被拒绝', async (): Promise<void> => {
    const id = randomUUID();
    const base = { id, email: `fixture-${id}@example.invalid`, name: '虚构律师', passwordHash: 'TEST_ONLY_HASH' };
    await expect(client.user.create({ data: { ...base, phone: cipher.encrypt('FICTIONAL-PHONE', `User:${id}:phone`) } })).rejects.toThrow();
    await expect(client.user.create({ data: { ...base, phone: new Uint8Array(Buffer.from('FICTIONAL-PLAINTEXT')),
      phoneLookupHash: cipher.blindIndex('FICTIONAL-PHONE', 'User.phone') } })).rejects.toThrow();
  });
  it('邮件凭据必须为密文，默认暂停，不开启真实轮询', async (): Promise<void> => {
    const user = await createUser();
    const id = randomUUID();
    const value = 'FICTIONAL-CREDENTIALS';
    const binding = await client.emailBinding.create({ data: { id, userId: user.id, email: user.email!, authType: 'APP_PASSWORD',
      credentials: cipher.encrypt(value, `EmailBinding:${id}:credentials`) } });
    expect(binding.status).toBe('PAUSED');
    expect(cipher.decrypt(binding.credentials, `EmailBinding:${id}:credentials`)).toBe(value);
    await expect(client.emailBinding.create({ data: { userId: user.id, email: 'other@example.invalid', authType: 'APP_PASSWORD',
      credentials: new Uint8Array(Buffer.from('FICTIONAL-PLAINTEXT-SHOULD-BE-REJECTED')) } })).rejects.toThrow();
  });
});
