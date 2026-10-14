import { INestApplication } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { requestTrace, ResponseEnvelope, SafeExceptionFilter } from './http-boundary';

/** 为运行实例和测试设置相同的 HTTP 安全边界。 */
export function configureApp(app: INestApplication): void {
  app.use(requestTrace);
  app.useGlobalInterceptors(new ResponseEnvelope());
  app.useGlobalFilters(new SafeExceptionFilter());
  app.enableShutdownHooks();
}

/** 创建开发应用；不打印框架启动信息或环境变量。 */
export async function createApp(): Promise<INestApplication> {
  const app = await NestFactory.create(AppModule, { logger: false });
  configureApp(app);
  return app;
}
