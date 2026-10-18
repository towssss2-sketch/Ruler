import { CanActivate, ExecutionContext, Inject, Injectable, NotFoundException, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { RUNTIME_PROFILE, RuntimeProfile } from '../../runtime-profile';

const DEVELOPMENT_ENTRY = 'ruler:development-entry';
export const DevelopmentEntry = (): MethodDecorator => SetMetadata(DEVELOPMENT_ENTRY, true);

/** 按路由处理器关闭开发入口；先于限流、鉴权和正文校验执行，不依赖可绕过的 URL 字符串匹配。 */
@Injectable()
export class DevelopmentEntryGuard implements CanActivate {
  constructor(private readonly reflector: Reflector, @Inject(RUNTIME_PROFILE) private readonly profile: RuntimeProfile) {}

  /** 模式在应用创建时固定，请求头、查询、正文及后续环境变量变更均不能打开入口。 */
  canActivate(context: ExecutionContext): boolean {
    if (this.profile === 'restricted-local' && this.reflector.get<boolean>(DEVELOPMENT_ENTRY, context.getHandler())) {
      throw new NotFoundException();
    }
    return true;
  }
}
