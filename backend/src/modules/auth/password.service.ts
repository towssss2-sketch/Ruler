import { Injectable } from '@nestjs/common';
import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

const PARAMETERS = { N: 32768, r: 8, p: 1, maxmem: 128 * 1024 * 1024 };

function derive(password: string, salt: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject): void => {
    scrypt(password, salt, 64, PARAMETERS, (error, key): void => {
      if (error) reject(new Error('密码处理暂不可用'));
      else resolve(key);
    });
  });
}

/** 固定成本的 scrypt 密码哈希；盐随机生成，不记录密码或哈希内容。 */
@Injectable()
export class PasswordService {
  /** 保存单向哈希；密码政策由 HTTP 输入校验层执行。 */
  async hash(password: string): Promise<string> {
    const salt = randomBytes(16);
    const key = await derive(password, salt);
    return `scrypt-v1$${salt.toString('hex')}$${key.toString('hex')}`;
  }

  /** 校验密码；格式异常同样完成一次固定成本计算，避免账号存在性差异。 */
  async verify(password: string, encoded: string): Promise<boolean> {
    const valid = /^scrypt-v1\$[a-f0-9]{32}\$[a-f0-9]{128}$/.test(encoded);
    const parts = encoded.split('$');
    const salt = valid ? Buffer.from(parts[1]!, 'hex') : Buffer.alloc(16);
    const expected = valid ? Buffer.from(parts[2]!, 'hex') : Buffer.alloc(64);
    const actual = await derive(password, salt);
    return timingSafeEqual(actual, expected) && valid;
  }
}
