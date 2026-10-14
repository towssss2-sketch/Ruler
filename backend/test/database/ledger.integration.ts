import { RTWallet } from '@prisma/client';
import { client, createUser } from './fixtures';

afterAll(async (): Promise<void> => { await client.$disconnect(); });

async function fundedWallet(amount = '100'): Promise<RTWallet> {
  const user = await createUser();
  return client.rTWallet.create({ data: {
    userId: user.id, balance: amount, totalCharged: amount,
    transactions: { create: { type: 'CHARGE', amount, balanceAfter: amount, remark: '虚构钱包初始化，非支付' } },
  } });
}

describe('RT 余额与连续流水快照', (): void => {
  it('初始钱包为零，不能创建无流水的非零余额', async (): Promise<void> => {
    const user = await createUser();
    await expect(client.rTWallet.create({ data: { userId: user.id, balance: '10' } })).rejects.toThrow();
    const wallet = await client.rTWallet.create({ data: { userId: user.id } });
    expect(wallet.balance.toString()).toBe('0');
  });
  it('禁止只修改钱包余额、不写流水', async (): Promise<void> => {
    const wallet = await fundedWallet();
    await expect(client.rTWallet.update({ where: { id: wallet.id }, data: { balance: '200' } })).rejects.toThrow();
    expect((await client.rTWallet.findUniqueOrThrow({ where: { id: wallet.id } })).balance.toString()).toBe('100');
  });
  it('禁止只插入流水、不一致更新钱包', async (): Promise<void> => {
    const wallet = await fundedWallet();
    await expect(client.rTTransaction.create({ data: { walletId: wallet.id, type: 'CONSUME_AI',
      amount: '-10', balanceAfter: '90' } })).rejects.toThrow();
    expect(await client.rTTransaction.count({ where: { walletId: wallet.id } })).toBe(1);
  });
  it('不接受错误快照，正确记账在同一事务完成并保留小数精度', async (): Promise<void> => {
    const wallet = await fundedWallet('1.5');
    await expect(client.$transaction([
      client.rTWallet.update({ where: { id: wallet.id }, data: { balance: '1.3' } }),
      client.rTTransaction.create({ data: { walletId: wallet.id, type: 'CONSUME_AI', amount: '-0.1', balanceAfter: '1.3' } }),
    ])).rejects.toThrow();
    await client.$transaction([
      client.rTWallet.update({ where: { id: wallet.id }, data: { balance: { decrement: '0.1' }, totalConsumed: { increment: '0.1' } } }),
      client.rTTransaction.create({ data: { walletId: wallet.id, type: 'CONSUME_AI', amount: '-0.1', balanceAfter: '1.4' } }),
    ]);
    expect((await client.rTWallet.findUniqueOrThrow({ where: { id: wallet.id } })).balance.toString()).toBe('1.4');
  });
  it('并发扣减不能使余额负数，失败事务不残留流水', async (): Promise<void> => {
    const wallet = await fundedWallet();
    const spend = async (): Promise<void> => {
      await client.$transaction(async (tx): Promise<void> => {
        const updated = await tx.rTWallet.update({ where: { id: wallet.id }, data: {
          balance: { decrement: '80' }, totalConsumed: { increment: '80' },
        } });
        await tx.rTTransaction.create({ data: { walletId: wallet.id, type: 'CONSUME_AI', amount: '-80', balanceAfter: updated.balance } });
      });
    };
    const result = await Promise.allSettled([spend(), spend()]);
    expect(result.filter((value): boolean => value.status === 'fulfilled')).toHaveLength(1);
    expect(result.filter((value): boolean => value.status === 'rejected')).toHaveLength(1);
    expect((await client.rTWallet.findUniqueOrThrow({ where: { id: wallet.id } })).balance.toString()).toBe('20');
    expect(await client.rTTransaction.count({ where: { walletId: wallet.id } })).toBe(2);
  });
});

describe('RT 流水只增不改与有限数值', (): void => {
  it('流水不能编辑、软删除或物理删除', async (): Promise<void> => {
    const wallet = await fundedWallet();
    const transaction = await client.rTTransaction.findFirstOrThrow({ where: { walletId: wallet.id } });
    await expect(client.rTTransaction.update({ where: { id: transaction.id }, data: { amount: '999' } })).rejects.toThrow();
    await expect(client.rTTransaction.update({ where: { id: transaction.id }, data: { deletedAt: new Date() } })).rejects.toThrow();
    await expect(client.rTTransaction.delete({ where: { id: transaction.id } })).rejects.toThrow();
    expect((await client.rTTransaction.findUniqueOrThrow({ where: { id: transaction.id } })).amount.toString()).toBe('100');
  });
  it('不接受负余额、NaN、零金额流水', async (): Promise<void> => {
    const wallet = await fundedWallet();
    await expect(client.rTWallet.update({ where: { id: wallet.id }, data: { balance: '-1' } })).rejects.toThrow();
    await expect(client.rTWallet.update({ where: { id: wallet.id }, data: { balance: 'NaN' } })).rejects.toThrow();
    await expect(client.rTTransaction.create({ data: { walletId: wallet.id, type: 'ADMIN_ADJUST', amount: '0', balanceAfter: '100' } }))
      .rejects.toThrow();
  });
  it('价格默认禁用，价格不能负数或 NaN', async (): Promise<void> => {
    const key = `fictional-price-${Date.now()}`;
    await expect(client.priceConfig.create({ data: { itemKey: key, itemType: 'AI', rtPrice: '-1' } })).rejects.toThrow();
    await expect(client.priceConfig.create({ data: { itemKey: key, itemType: 'AI', rtPrice: 'NaN' } })).rejects.toThrow();
    const price = await client.priceConfig.create({ data: { itemKey: key, itemType: 'AI', rtPrice: '1.25' } });
    expect(price.enabled).toBe(false);
    expect(price.rtPrice.toString()).toBe('1.25');
  });
});
