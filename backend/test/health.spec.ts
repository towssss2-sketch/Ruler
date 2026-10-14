import { ServiceUnavailableException } from '@nestjs/common';
import { HealthService } from '../src/health.service';
import { PrismaRepository } from '../src/prisma.repository';

describe('健康服务', (): void => {
  const checkConnection = jest.fn<Promise<void>, []>();
  const service = new HealthService({ checkConnection } as unknown as PrismaRepository);
  beforeEach((): void => { checkConnection.mockReset(); });
  it('存活检查不访问数据库', (): void => {
    expect(service.live()).toEqual({ status: 'ok', stage: 0 });
    expect(checkConnection).not.toHaveBeenCalled();
  });
  it('就绪检查必须访问数据库', async (): Promise<void> => {
    checkConnection.mockResolvedValueOnce(undefined);
    await expect(service.ready()).resolves.toEqual({ status: 'ok', stage: 0 });
    expect(checkConnection).toHaveBeenCalledTimes(1);
  });
  it('数据库失败不能伪报就绪或泄露异常', async (): Promise<void> => {
    checkConnection.mockRejectedValueOnce(new Error('fictional-private-connection'));
    await expect(service.ready()).rejects.toEqual(
      new ServiceUnavailableException('开发数据库暂不可用'),
    );
  });
});
