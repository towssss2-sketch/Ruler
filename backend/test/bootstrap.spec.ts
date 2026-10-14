import { createApp } from '../src/create-app';
import { HealthService } from '../src/health.service';

describe('正式应用工厂', (): void => {
  it('实际创建应用并处理存活请求与未知内部异常', async (): Promise<void> => {
    const app = await createApp();
    try {
      await app.listen(0, '127.0.0.1');
      const baseUrl = await app.getUrl();
      const ok = await fetch(`${baseUrl}/health`);
      expect(ok.status).toBe(200);
      const spy = jest.spyOn(HealthService.prototype, 'live')
        .mockImplementationOnce((): never => { throw new Error('fictional-private-stack'); });
      try {
        const failed = await fetch(`${baseUrl}/health`);
        expect(failed.status).toBe(500);
        expect(await failed.text()).not.toContain('fictional-private-stack');
      } finally { spy.mockRestore(); }
    } finally { await app.close(); }
  });
});
