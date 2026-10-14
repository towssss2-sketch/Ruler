import { PrismaRepository } from '../src/prisma.repository';

const query = jest.fn<Promise<unknown>, unknown[]>();
const disconnect = jest.fn<Promise<void>, []>();
jest.mock('@prisma/client', (): object => ({
  PrismaClient: jest.fn().mockImplementation((): object => ({
    $queryRaw: query, $disconnect: disconnect,
  })),
}));

describe('Prisma 生命周期和参数化探针', (): void => {
  beforeEach((): void => { query.mockReset(); disconnect.mockReset(); });
  it('通过 Prisma tagged-template 执行固定 SELECT 1', async (): Promise<void> => {
    query.mockResolvedValueOnce([{ '?column?': 1 }]);
    const repository = new PrismaRepository();
    await repository.checkConnection();
    expect(query).toHaveBeenCalledWith(['SELECT 1']);
  });
  it('数据库异常保留给服务层处理', async (): Promise<void> => {
    query.mockRejectedValueOnce(new Error('fictional-db-failure'));
    await expect(new PrismaRepository().checkConnection()).rejects.toThrow('fictional-db-failure');
  });
  it('关闭应用释放数据库连接', async (): Promise<void> => {
    await new PrismaRepository().onModuleDestroy();
    expect(disconnect).toHaveBeenCalledTimes(1);
  });
});
