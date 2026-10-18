import { mkdtempSync, readFileSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { createServer } from 'node:https';
import { request } from 'node:http';

/** 测试专用临时自签证书，只含本机 IP；不安装到系统、不写入仓库或输出私钥。 */
export function testTlsFixture() {
  const root = mkdtempSync(join(tmpdir(), 'ruler-fictional-tls-'));
  const certFile = join(root, 'certificate.pem');
  const keyFile = join(root, 'private.pem');
  try {
    execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-noenc', '-days', '1',
      '-keyout', keyFile, '-out', certFile, '-subj', '/CN=Ruler-Fictional-Loopback',
      '-addext', 'subjectAltName=IP:127.0.0.1'], { stdio: 'ignore' });
    chmodSync(certFile, 0o600); chmodSync(keyFile, 0o600);
    return { certFile, keyFile, cert: readFileSync(certFile), key: readFileSync(keyFile),
      close: () => rmSync(root, { recursive: true, force: true }) };
  } catch { rmSync(root, { recursive: true, force: true }); throw new Error('本机测试证书准备失败'); }
}

/** 测试专用 HTTPS 文件入口：固定本机上游、保留 Host，不读取或记录正文及签名。 */
export async function tlsStorageFixture(endpoint, tls) {
  const target = new URL(endpoint);
  if (target.protocol !== 'http:' || !['127.0.0.1', 'localhost'].includes(target.hostname)
    || target.username || target.password || target.pathname !== '/' || target.search || target.hash) throw new Error('仅允许本机测试存储');
  const state = { put: 0, get: 0, credentialHeaderObserved: false };
  const server = createServer({ cert: tls.cert, key: tls.key, minVersion: 'TLSv1.2' }, (incoming, outgoing) => {
    if (!['PUT', 'GET'].includes(incoming.method)) { outgoing.writeHead(405).end(); return; }
    state[incoming.method.toLowerCase()]++;
    if (incoming.headers.authorization || incoming.headers.cookie) state.credentialHeaderObserved = true;
    const upstream = request({ hostname: target.hostname, port: target.port, path: incoming.url,
      method: incoming.method, headers: incoming.headers, agent: false }, response => {
      outgoing.writeHead(response.statusCode ?? 502, response.headers);
      response.on('error', () => outgoing.destroy()); response.pipe(outgoing);
    });
    upstream.on('error', () => { if (!outgoing.headersSent) outgoing.writeHead(502); outgoing.end(); });
    upstream.setTimeout(10000, () => upstream.destroy());
    incoming.on('error', () => upstream.destroy()); outgoing.on('close', () => upstream.destroy());
    incoming.pipe(upstream);
  });
  await new Promise((resolve, reject) => {
    server.once('error', () => reject(new Error('本机 HTTPS 测试入口启动失败')));
    server.listen(0, '127.0.0.1', resolve);
  });
  return { origin: `https://127.0.0.1:${server.address().port}`, state, async close() {
    server.closeAllConnections();
    await new Promise((resolve, reject) => server.close(error => error ? reject(new Error('测试入口关闭失败')) : resolve()));
  } };
}
