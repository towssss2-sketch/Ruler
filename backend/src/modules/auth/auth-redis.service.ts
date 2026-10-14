import { Inject, Injectable, OnModuleDestroy, ServiceUnavailableException, HttpException } from '@nestjs/common';
import { createHmac, randomInt } from 'node:crypto';
import Redis from 'ioredis';
import { AUTH_CONFIG, AuthConfig } from './auth-config';
import { DevelopmentMailbox } from './development-mailbox';

const LIMIT = `local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('EXPIRE',KEYS[1],ARGV[1]) end; return n`;
const CONSUME = `local h=redis.call('HGET',KEYS[1],'hash'); if not h then return 0 end;
if h==ARGV[1] then redis.call('DEL',KEYS[1]); return 1 end;
local n=redis.call('HINCRBY',KEYS[1],'attempts',1); if n>=5 then redis.call('DEL',KEYS[1]) end; return 0`;

/** 验证码与严格限流依赖 Redis，服务异常时关闭入口，不能内存降级放行。 */
@Injectable()
export class AuthRedisService implements OnModuleDestroy {
  private readonly redis: Redis;
  private connection?: Promise<void>;
  constructor(@Inject(AUTH_CONFIG) private readonly config: AuthConfig, private readonly mailbox: DevelopmentMailbox) {
    this.redis = new Redis(config.REDIS_URL, { lazyConnect: true, enableOfflineQueue: false,
      maxRetriesPerRequest: 0, retryStrategy: (): null => null, connectTimeout: 2000 });
    this.redis.on('error', (): void => { /* 错误可能包含连接信息，禁止直接日志输出。 */ });
  }

  /** 稳定 HMAC 标识，不在 Redis 键中保存邮箱/IP/验证码明文。 */
  digest(value: string, purpose: string): string {
    return createHmac('sha256', Buffer.from(this.config.AUTH_CHALLENGE_KEY, 'hex'))
      .update(JSON.stringify([purpose, value])).digest('hex');
  }

  private async ready(): Promise<void> {
    if (this.redis.status === 'ready') return;
    this.connection ??= this.redis.connect().then((): void => undefined)
      .catch((): never => { throw new ServiceUnavailableException(); })
      .finally((): void => { this.connection = undefined; });
    await this.connection;
  }

  /** 按账户与来源分别限流，Lua 保证计数和首次过期设置原子完成。 */
  async limit(kind: string, value: string, maximum: number): Promise<void> {
    await this.ready();
    let count: unknown;
    try { count = await this.redis.eval(LIMIT, 1, `${this.config.AUTH_REDIS_PREFIX}limit:${kind}:${this.digest(value, kind)}`, 60); }
    catch { throw new ServiceUnavailableException(); }
    if (typeof count !== 'number') throw new ServiceUnavailableException();
    if (count > maximum) throw new HttpException('请求过于频繁', 429);
  }

  /** 生成一次性六位随机码，仅以 HMAC 保存在 Redis，十分钟失效。 */
  async requestCode(email: string): Promise<void> {
    if (!email.endsWith('@example.invalid')) await this.mailbox.send(email, '');
    await this.ready();
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const key = `${this.config.AUTH_REDIS_PREFIX}code:${this.digest(email, 'email')}`;
    try {
      const result = await this.redis.multi().hset(key, 'hash', this.digest(`${email}:${code}`, 'code'), 'attempts', '0').expire(key, 600).exec();
      if (!result || result.some(([error]): boolean => error !== null)) throw new Error();
    } catch { throw new ServiceUnavailableException(); }
    await this.mailbox.send(email, code);
  }

  /** 原子消费验证码；错误最多尝试五次，不存在/过期/错误统一返回 false。 */
  async consumeCode(email: string, code: string): Promise<boolean> {
    await this.ready();
    try {
      return await this.redis.eval(CONSUME, 1, `${this.config.AUTH_REDIS_PREFIX}code:${this.digest(email, 'email')}`,
        this.digest(`${email}:${code}`, 'code')) === 1;
    } catch { throw new ServiceUnavailableException(); }
  }

  /** 关闭连接，不输出 Redis 信息。 */
  async onModuleDestroy(): Promise<void> { this.redis.disconnect(); }
}
