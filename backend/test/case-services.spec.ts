import { randomBytes, randomUUID } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { CaseWriteService } from '../src/modules/case/case-write.service';
import { CasePartiesService } from '../src/modules/case/case-parties.service';
import { CaseViewService } from '../src/modules/case/case-view.service';
import { CaseReadService } from '../src/modules/case/case-read.service';
import { configuredCipher } from '../src/encryption-config';
import { EncryptionService } from '../src/encryption.service';
import { PrismaRepository } from '../src/prisma.repository';
import { CaseQuery } from '../src/modules/case/case-input';
import { lockCase } from '../src/modules/case/case-transaction';
import { input } from './case/fixture';

describe('案件服务单元：错误与授权分支', (): void => {
  const cipher = new EncryptionService(randomBytes(32));
  const parties = new CasePartiesService(cipher);
  const view = new CaseViewService(cipher);
  it('未提供、清空和明文分别保留、清空、加密；错误 AAD 拒绝解密', (): void => {
    expect(parties.encrypt(undefined, 'Case:test:notes')).toBeUndefined();
    expect(parties.encrypt(null, 'Case:test:notes')).toBeNull();
    const bytes = parties.encrypt('fictional', 'Case:test:notes')!;
    expect(cipher.decrypt(bytes, 'Case:test:notes') === 'fictional').toBe(true);
    expect((): string => cipher.decrypt(bytes, 'Case:other:notes')).toThrow();
  });
  it('未知数据库错误不伪装成重复案件；已无重复记录时保留原错误', async (): Promise<void> => {
    const error = new Error('fictional');
    const tx = jest.fn().mockRejectedValue(error);
    const find = jest.fn().mockResolvedValue(null);
    const repository = { db: { $transaction: tx, case: { findFirst: find } } } as unknown as PrismaRepository;
    const service = new CaseWriteService(repository, parties, view);
    await expect(service.create(randomUUID(), input())).rejects.toBe(error);
    const unique = new Prisma.PrismaClientKnownRequestError('fictional', { code: 'P2002', clientVersion: 'test' });
    tx.mockRejectedValue(unique);
    await expect(service.create(randomUUID(), input())).rejects.toBe(unique);
    expect(find).toHaveBeenCalledTimes(1);
    await expect(service.update(randomUUID(), randomUUID(), { cause: '虚构' })).rejects.toBe(unique);
    expect(find).toHaveBeenCalledTimes(1);
  });
  it('协作列表明确未启用且不查库；锁内再次核验失败即拒绝', async (): Promise<void> => {
    const repository = { db: {} } as PrismaRepository;
    const service = new CaseReadService(repository, view);
    const query = Object.assign(new CaseQuery(), { group: 'collaborated' });
    await expect(service.list(randomUUID(), query)).resolves.toMatchObject({ items: [], collaborationEnabled: false });
    const tx = { $queryRaw: jest.fn().mockResolvedValue([]) } as unknown as Prisma.TransactionClient;
    await expect(lockCase(tx, randomUUID(), randomUUID(), true)).rejects.toThrow('Forbidden');
  });
});

describe('字段加密配置', (): void => {
  it('拒绝缺失、错误长度、生产环境和复用鉴权密钥，错误不包含值', (): void => {
    const key = randomBytes(32).toString('hex');
    expect((): unknown => configuredCipher({ NODE_ENV: 'test' })).toThrow('字段加密配置无效');
    expect((): unknown => configuredCipher({ NODE_ENV: 'test', FIELD_ENCRYPTION_KEY: 'fictional' })).toThrow('字段加密配置无效');
    expect((): unknown => configuredCipher({ NODE_ENV: 'production', FIELD_ENCRYPTION_KEY: key })).toThrow();
    expect((): unknown => configuredCipher({ NODE_ENV: 'test', FIELD_ENCRYPTION_KEY: key, AUTH_SIGNING_KEY: key })).toThrow('必须独立生成');
    expect(configuredCipher({ NODE_ENV: 'test', FIELD_ENCRYPTION_KEY: key })).toBeInstanceOf(EncryptionService);
  });
});
