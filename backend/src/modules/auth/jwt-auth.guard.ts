import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthRequest, PUBLIC_ROUTE } from './auth-decorators';
import { SessionService } from './session.service';

/** 全局默认拒绝匿名访问，只有明确 PublicRoute 标记允许公开。 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly reflector: Reflector, private readonly sessions: SessionService) {}

  /** 严格提取单个 Bearer 令牌，不接受 URL、正文、Cookie 或重复凭据。 */
  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (this.reflector.getAllAndOverride<boolean>(PUBLIC_ROUTE, [context.getHandler(), context.getClass()])) return true;
    const request = context.switchToHttp().getRequest<AuthRequest>();
    const authorization = request.headers.authorization;
    const count = request.rawHeaders.filter((value, index): boolean => index % 2 === 0 && value.toLowerCase() === 'authorization').length;
    if (count !== 1 || !authorization || !/^Bearer [A-Za-z0-9_.-]{1,4096}$/.test(authorization)) throw new UnauthorizedException();
    request.principal = await this.sessions.authenticate(authorization.slice(7));
    return true;
  }
}
