import { ChildProcess, fork } from 'node:child_process';
import { resolve } from 'node:path';
import { Reply } from '../auth/fixture';

interface ProcessMessage { type: string; origin?: string }
export interface PreviewProcess {
  child: ChildProcess;
  origin: string;
  exited: Promise<{ code: number | null; signal: NodeJS.Signals | null }>;
}

/** 仅接受固定 IPC 消息；超时/退出时清理监听器，不回显子进程日志或环境变量。 */
export function message(child: ChildProcess, type: string): Promise<ProcessMessage> {
  return new Promise((resolveMessage, reject) => {
    const cleanup = (): void => { clearTimeout(timer); child.off('message', receive); child.off('exit', fail); child.off('error', fail); };
    const fail = (): void => { cleanup(); reject(new Error('隔离后端子进程未按预期就绪')); };
    const receive = (value: unknown): void => {
      if (typeof value !== 'object' || value === null || !('type' in value) || value.type !== type) return;
      cleanup(); resolveMessage(value as ProcessMessage);
    };
    const timer = setTimeout(fail, 15000);
    child.on('message', receive); child.once('exit', fail); child.once('error', fail);
    if (child.exitCode !== null || child.signalCode !== null) fail();
  });
}

/** 派生真正的 Node/Nest 进程；第一实例只在存储 read 接缝暂停，重启实例完全使用实际驱动。 */
export async function startPreviewProcess(pauseRead: boolean): Promise<PreviewProcess> {
  const child = fork(resolve(__dirname, '../../../scripts/preview-restart-server.mjs'), pauseRead ? ['--pause-read'] : [],
    { env: { ...process.env }, execArgv: [], stdio: ['ignore', 'ignore', 'ignore', 'ipc'] });
  const exited = new Promise<{ code: number | null; signal: NodeJS.Signals | null }>((done) => {
    child.once('exit', (code, signal) => done({ code, signal }));
    child.once('error', () => done({ code: 1, signal: null }));
  });
  try {
    const ready = await message(child, 'READY');
    if (!ready.origin || !/^http:\/\/127\.0\.0\.1:\d+$/.test(ready.origin)) throw new Error('测试进程地址无效');
    return { child, origin: ready.origin, exited };
  } catch {
    child.kill('SIGKILL'); await exited;
    throw new Error('无法启动隔离后端子进程');
  }
}

/** 有界关闭本次派生进程，异常时强制回收，不影响开发服务。 */
export async function stopPreviewProcess(server: PreviewProcess): Promise<void> {
  if (server.child.exitCode !== null || server.child.signalCode !== null) return;
  const timer = setTimeout(() => server.child.kill('SIGKILL'), 5000);
  try { server.child.kill('SIGTERM'); await server.exited; }
  finally { clearTimeout(timer); }
}

/** 真实 HTTP 请求；失败只抛固定说明，令牌和原始网络异常不进入日志。 */
export async function processRequest(server: PreviewProcess, path: string, access: string, body?: unknown): Promise<Reply> {
  try {
    const response = await fetch(`${server.origin}${path}`, { method: body === undefined ? 'GET' : 'POST',
      headers: { authorization: `Bearer ${access}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000) });
    const raw = await response.text();
    const envelope = JSON.parse(raw) as { data: Record<string, unknown> | null };
    return { status: response.status, data: envelope.data ?? {}, raw };
  } catch { throw new Error('隔离后端请求未完成'); }
}
