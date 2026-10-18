import 'reflect-metadata';
import { loadConfig } from './config';
import { createApp } from './create-app';

/** 启动仅面向开发的应用；配置错误时非零退出，显式 HTTPS 配置失败不降级。 */
async function bootstrap(): Promise<void> {
  const config = loadConfig(process.env);
  const app = await createApp();
  await app.listen(config.PORT, config.HOST);
}

void bootstrap().catch((): void => {
  console.error('启动失败，请检查本地开发配置和服务状态');
  process.exitCode = 1;
});
