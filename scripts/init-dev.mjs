import { randomBytes } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// 只生成本地开发凭据，不读取或输出已有凭据；已有 .env 不覆盖。
const password = randomBytes(24).toString('hex');
const minioPassword = randomBytes(24).toString('hex');
const databaseUrl = new URL('postgresql://127.0.0.1:5432/ruler_dev?schema=public&connection_limit=3&connect_timeout=5');
databaseUrl.username = 'ruler_dev';
databaseUrl.password = password;
const file = fileURLToPath(new URL('../.env', import.meta.url));
const contents = [
  'NODE_ENV=development', 'HOST=127.0.0.1', 'PORT=3000',
  'POSTGRES_USER=ruler_dev', 'POSTGRES_DB=ruler_dev',
  `POSTGRES_PASSWORD=${password}`,
  `DATABASE_URL=${databaseUrl.toString()}`,
  'REDIS_URL=redis://127.0.0.1:6379',
  'MINIO_ROOT_USER=ruler_dev', `MINIO_ROOT_PASSWORD=${minioPassword}`,
  'MINIO_ENDPOINT=http://127.0.0.1:9000',
  '',
].join('\n');
try {
  writeFileSync(file, contents, { flag: 'wx', mode: 0o600 });
  console.log('已生成仅供本地开发的 .env（已忽略，不提交）；未输出凭据。');
} catch (error) {
  if (error.code !== 'EEXIST') throw error;
  console.log('保留已有 .env，未覆盖。');
}
