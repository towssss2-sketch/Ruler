import { randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// 仅向已忽略的本地开发 .env 添加缺失配置；已有密钥不覆盖，不输出内容。
const path = fileURLToPath(new URL('../.env', import.meta.url));
let contents = readFileSync(path, 'utf8');
if (!/^NODE_ENV=(development|test)$/m.test(contents)) throw new Error('只允许明确开发或测试环境');
for (const key of ['AUTH_SIGNING_KEY', 'AUTH_CHALLENGE_KEY', 'FIELD_ENCRYPTION_KEY']) {
  if (!new RegExp(`^${key}=`, 'm').test(contents)) contents += `\n${key}=${randomBytes(32).toString('hex')}\n`;
}
writeFileSync(path, contents, { mode: 0o600 });
chmodSync(path, 0o600);
console.log('PASS 本地开发鉴权配置就绪；未打印或覆盖已有密钥');
