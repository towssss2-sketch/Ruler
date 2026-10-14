import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AppModule } from '../src/app.module';
import { PrismaRepository } from '../src/prisma.repository';
import { ResponseEnvelope, SafeExceptionFilter } from '../src/http-boundary';

describe('缺失 trace 中间件时的安全兜底', (): void => {
  let app: INestApplication;
  beforeAll(async (): Promise<void> => {
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaRepository).useValue({}).compile();
    app = module.createNestApplication({ logger: false });
    app.useGlobalInterceptors(new ResponseEnvelope());
    app.useGlobalFilters(new SafeExceptionFilter());
    await app.listen(0, '127.0.0.1');
  });
  afterAll(async (): Promise<void> => { await app.close(); });
  it.each(['/health', '/not-found'])('%s 仍返回可追踪响应', async (path: string): Promise<void> => {
    const response = await fetch(`${await app.getUrl()}${path}`);
    const body = await response.json() as { traceId: string };
    expect(body.traceId).toMatch(/^[0-9a-f-]{36}$/);
  });
});
