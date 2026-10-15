import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// 只补充非敏感开发配置；沿用本地 MinIO 凭据，不创建或要求真实 OSS 凭据。
const path = fileURLToPath(new URL('../.env', import.meta.url));
let contents = readFileSync(path, 'utf8');
if (!/^NODE_ENV=(development|test)$/m.test(contents)) throw new Error('只允许明确开发或测试环境');
const values = { STORAGE_DRIVER: 'minio', STORAGE_BUCKET: 'ruler-dev', STORAGE_REGION: 'us-east-1', STORAGE_SIGNED_URL_TTL_SECONDS: '600' };
for (const [key, value] of Object.entries(values)) {
  if (!new RegExp(`^${key}=`, 'm').test(contents)) contents += `\n${key}=${value}\n`;
}
writeFileSync(path, contents, { mode: 0o600 });
chmodSync(path, 0o600);
console.log('PASS 本地开发存储配置就绪；未覆盖已有配置，未读取或创建 OSS 凭据');
