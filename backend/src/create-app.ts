import { INestApplication } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { requestTrace, ResponseEnvelope, SafeExceptionFilter } from './http-boundary';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

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
  const document = SwaggerModule.createDocument(app, new DocumentBuilder().setTitle('RULER 开发接口')
    .setDescription('仅虚构数据；验证码无真实邮件投递；业务 CRUD 尚未实现。').setVersion('0.2').addBearerAuth().build());
  SwaggerModule.setup('docs', app, document, { swaggerOptions: { persistAuthorization: false } });
  return app;
}
