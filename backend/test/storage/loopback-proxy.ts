import { createServer, request } from 'node:http';
import { AddressInfo } from 'node:net';

interface LoopbackProxy {
  origin: string;
  methods: string[];
  rewriteHost: boolean;
  close(): Promise<void>;
}

/** 仅供测试：本机独立端口转发到固定本机 MinIO，保留原 Host/路径，不记录签名或正文。 */
export async function loopbackProxy(endpoint: string): Promise<LoopbackProxy> {
  const target = new URL(endpoint);
  if (target.protocol !== 'http:' || !['127.0.0.1', 'localhost'].includes(target.hostname)
    || target.username || target.password || target.pathname !== '/' || target.search || target.hash) throw new Error('测试入口仅允许本机 HTTP 存储');
  const proxy: LoopbackProxy = { origin: '', methods: [], rewriteHost: false,
    close: async (): Promise<void> => {
      server.closeAllConnections();
      await new Promise<void>((resolve, reject): void => {
        server.close((error): void => { if (error) reject(new Error('本机测试入口关闭失败')); else resolve(); });
      });
    } };
  const server = createServer((incoming, outgoing): void => {
    proxy.methods.push(incoming.method ?? 'UNKNOWN');
    if (!['PUT', 'GET'].includes(incoming.method ?? '')) { outgoing.writeHead(405).end(); return; }
    const headers = { ...incoming.headers, ...(proxy.rewriteHost ? { host: target.host } : {}) };
    const upstream = request({ hostname: target.hostname, port: target.port, path: incoming.url,
      method: incoming.method, headers, agent: false }, (response): void => {
      outgoing.writeHead(response.statusCode ?? 502, response.headers);
      response.on('error', (): void => { outgoing.destroy(); });
      response.pipe(outgoing);
    });
    upstream.on('error', (): void => {
      if (!outgoing.headersSent) outgoing.writeHead(502);
      outgoing.end();
    });
    upstream.setTimeout(10000, (): void => { upstream.destroy(); });
    incoming.on('error', (): void => { upstream.destroy(); });
    outgoing.on('close', (): void => { upstream.destroy(); });
    incoming.pipe(upstream);
  });
  await new Promise<void>((resolve, reject): void => {
    server.once('error', (): void => { reject(new Error('本机测试入口启动失败')); });
    server.listen(0, '127.0.0.1', (): void => { resolve(); });
  });
  proxy.origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return proxy;
}
