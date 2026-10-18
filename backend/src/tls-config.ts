import { readFileSync, statSync } from 'node:fs';
import { isAbsolute } from 'node:path';
import { createSecureContext, SecureContextOptions } from 'node:tls';
import { X509Certificate } from 'node:crypto';
import { z } from 'zod';

const filePath = z.string().min(1).refine(isAbsolute);
const schema = z.object({ NODE_ENV: z.enum(['development', 'test']), HOST: z.enum(['127.0.0.1', 'localhost']),
  RULER_TLS_CERT_FILE: filePath, RULER_TLS_KEY_FILE: filePath });

/** 显式启用本机 TLS；配对、有效期、主机及文件错误均拒绝启动，不降级 HTTP、不回显内容或路径。 */
export function loadTlsOptions(environment: NodeJS.ProcessEnv): SecureContextOptions | undefined {
  if (environment.RULER_TLS_CERT_FILE === undefined && environment.RULER_TLS_KEY_FILE === undefined) return undefined;
  try {
    const config = schema.parse(environment);
    const cert = readMaterial(config.RULER_TLS_CERT_FILE);
    const key = readMaterial(config.RULER_TLS_KEY_FILE);
    const leaf = new X509Certificate(cert);
    const now = Date.now();
    const matches = config.HOST === 'localhost' ? leaf.checkHost('localhost') : leaf.checkIP(config.HOST);
    if (!matches || Date.parse(leaf.validFrom) > now || Date.parse(leaf.validTo) <= now) throw new Error('certificate');
    const options: SecureContextOptions = { cert, key, minVersion: 'TLSv1.2' };
    createSecureContext(options); // 验证私钥与叶证书配对；不输出材料。
    return options;
  } catch { throw new Error('本机 HTTPS 配置无效'); }
}

/** 只读取有界普通文件；密钥与证书仅保留在进程内存。 */
function readMaterial(path: string): Buffer {
  const stat = statSync(path);
  if (!stat.isFile() || stat.size < 1 || stat.size > 128 * 1024) throw new Error('material');
  return readFileSync(path);
}
