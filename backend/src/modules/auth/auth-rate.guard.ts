import { CanActivate, ExecutionContext, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthRequest, PUBLIC_ROUTE } from './auth-decorators';
import { AuthRedisService } from './auth-redis.service';

const RATE_KIND = 'ruler:auth-rate';
type RateKind = 'code' | 'register' | 'login' | 'refresh';
export const RateLimit = (kind: RateKind): MethodDecorator => SetMetadata(RATE_KIND, kind);

@Injectable()
export class AuthRateGuard implements CanActivate {
  constructor(private readonly reflector: Reflector, private readonly redis: AuthRedisService) {}

  /** 来源 IP 采用直接连接地址，不信任转发头；账户键规范化后进行独立限制。 */
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const kind = this.reflector.get<RateKind>(RATE_KIND, context.getHandler());
    const request = context.switchToHttp().getRequest<AuthRequest>();
    if (!kind) {
      if (this.reflector.getAllAndOverride<boolean>(PUBLIC_ROUTE, [context.getHandler(), context.getClass()])) return true;
      await this.redis.limit('api-source', request.ip ?? 'unknown', 120);
      return true;
    }
    await this.redis.limit('source', request.ip ?? 'unknown', 30);
    const body = request.body as unknown;
    if (body && typeof body === 'object' && 'email' in body && typeof body.email === 'string') {
      await this.redis.limit(kind, body.email.trim().toLowerCase().slice(0, 254), kind === 'code' ? 3 : 5);
    }
    return true;
  }
}
