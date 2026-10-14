import { defineConfig } from 'prisma/config';

// Prisma 6 原生多文件 Schema；数据库 URL 仍由 Schema 的环境变量解析。
export default defineConfig({
  schema: 'prisma',
  migrations: { path: 'prisma/migrations' },
});
