import 'reflect-metadata';
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AddressInfo } from 'node:net';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/create-app';
import { PrismaRepository } from '../src/prisma.repository';

describe('真实 HTTP 冒烟和错误路径', (): void => {
  let app: INestApplication;
  let baseUrl: string;
  const checkConnection = jest.fn<Promise<void>, []>();

  beforeAll(async (): Promise<void> => {
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaRepository).useValue({ checkConnection }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    const address = app.getHttpServer().address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;
  });
  afterAll(async (): Promise<void> => { await app.close(); });
  beforeEach((): void => { checkConnection.mockReset(); });

  it('GET /health 返回标准响应和服务端 traceId', async (): Promise<void> => {
    const response = await fetch(`${baseUrl}/health`, { headers: { 'x-trace-id': 'untrusted' } });
    const body = await response.json() as Record<string, unknown>;
    expect(response.status).toBe(200);
    expect(body).toMatchObject({ code: 0, message: 'ok', data: { status: 'ok', stage: 0 } });
    expect(body.traceId).toMatch(/^[0-9a-f-]{36}$/);
    expect(response.headers.get('x-trace-id')).toBe(body.traceId);
  });
  it('GET /health/ready 实际调用仓库检查', async (): Promise<void> => {
    checkConnection.mockResolvedValueOnce(undefined);
    const response = await fetch(`${baseUrl}/health/ready`);
    expect(response.status).toBe(200);
    expect(checkConnection).toHaveBeenCalledTimes(1);
  });
  it('数据库错误返回 503 且不含底层异常', async (): Promise<void> => {
    checkConnection.mockRejectedValueOnce(new Error('fictional-private-connection'));
    const response = await fetch(`${baseUrl}/health/ready`);
    expect(response.status).toBe(503);
    const body = await response.text();
    expect(body).toContain('服务暂不可用');
    expect(body).not.toContain('fictional-private-connection');
    expect(body).not.toContain('stack');
  });
  it('未实现业务路由返回 404，不回显查询输入', async (): Promise<void> => {
    const response = await fetch(`${baseUrl}/cases?private=fictional-sensitive-input`);
    expect(response.status).toBe(404);
    const body = await response.text();
    expect(body).toContain('接口不存在');
    expect(body).not.toContain('fictional-sensitive-input');
  });
});
