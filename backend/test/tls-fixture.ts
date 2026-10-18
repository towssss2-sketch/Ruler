import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { get } from 'node:https';

/** 仅创建并清理本次随机目录中的自签证书；不记录密钥，不修改系统信任库。 */
export function tlsFixture(): { root: string; cert: string; key: string; environment: NodeJS.ProcessEnv; close(): void } {
  const root = mkdtempSync(join(tmpdir(), 'ruler-tls-unit-'));
  const cert = join(root, 'certificate.pem');
  const key = join(root, 'private.pem');
  try {
    execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-noenc', '-days', '1',
      '-keyout', key, '-out', cert, '-subj', '/CN=Ruler-Fictional-Loopback',
      '-addext', 'subjectAltName=IP:127.0.0.1'], { stdio: 'ignore' });
    chmodSync(cert, 0o600); chmodSync(key, 0o600);
  } catch { rmSync(root, { recursive: true, force: true }); throw new Error('测试证书生成失败'); }
  return { root, cert, key, environment: { NODE_ENV: 'test', HOST: '127.0.0.1',
    RULER_TLS_CERT_FILE: cert, RULER_TLS_KEY_FILE: key }, close: (): void => { rmSync(root, { recursive: true, force: true }); } };
}

/** 实际 HTTPS 握手；始终保留证书校验，仅返回状态或固定错误类别，不回显路径或响应。 */
export async function tlsGet(origin: string, cert?: string, servername?: string): Promise<number> {
  return new Promise<number>((resolve, reject): void => {
    const req = get(`${origin}/health`, { ...(cert ? { ca: readFileSync(cert) } : {}),
      ...(servername ? { servername } : {}), agent: false }, (response): void => {
      response.resume(); response.on('end', (): void => { resolve(response.statusCode ?? 0); });
      response.on('error', (): void => { reject(new Error('HTTPS_RESPONSE_FAILED')); });
    });
    req.setTimeout(5000, (): void => { req.destroy(new Error('timeout')); });
    req.on('error', (error: NodeJS.ErrnoException): void => {
      reject(new Error(error.code === 'ERR_TLS_CERT_ALTNAME_INVALID' ? 'HOSTNAME_REJECTED' : 'TLS_REJECTED'));
    });
  });
}
