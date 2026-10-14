import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { AUTH_CONFIG, AuthConfig } from './auth-config';
import { AuthPrincipal } from './auth-decorators';

const claims = z.object({ sub: z.string().uuid(), sid: z.string().uuid(), jti: z.string().uuid(),
  type: z.literal('access'), iat: z.number().int(), exp: z.number().int() });

/** 只签发短期 Access JWT，刷新令牌使用独立随机凭据，防止类型混淆。 */
@Injectable()
export class TokenCodecService {
  private readonly jwt: JwtService;
  constructor(@Inject(AUTH_CONFIG) config: AuthConfig) {
    this.jwt = new JwtService({ secret: Buffer.from(config.AUTH_SIGNING_KEY, 'hex'),
      signOptions: { algorithm: 'HS256', issuer: 'ruler-development', audience: 'ruler-client', expiresIn: 7200 },
      verifyOptions: { algorithms: ['HS256'], issuer: 'ruler-development', audience: 'ruler-client' } });
  }

  /** 签发带会话 ID 的两小时令牌，不放入手机号、姓名、邮箱或角色缓存。 */
  async sign(userId: string, sessionId: string): Promise<string> {
    return this.jwt.signAsync({ sub: userId, sid: sessionId, jti: randomUUID(), type: 'access' });
  }

  /** 固定算法、签发者、受众、期限和类型；错误统一返回 401。 */
  async verify(token: string): Promise<AuthPrincipal> {
    try {
      const parsed = claims.parse(await this.jwt.verifyAsync<Record<string, unknown>>(token));
      if (parsed.exp - parsed.iat !== 7200 || parsed.iat > Math.floor(Date.now() / 1000)) throw new Error();
      return { userId: parsed.sub, sessionId: parsed.sid };
    } catch { throw new UnauthorizedException(); }
  }
}
