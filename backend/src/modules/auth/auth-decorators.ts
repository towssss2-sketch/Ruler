import { createParamDecorator, ExecutionContext, SetMetadata } from '@nestjs/common';
import { TracedRequest } from '../../http-boundary';

export interface AuthPrincipal { userId: string; sessionId: string }
export interface AuthRequest extends TracedRequest { principal?: AuthPrincipal }
export const PUBLIC_ROUTE = 'ruler:public';
export const PublicRoute = (): MethodDecorator & ClassDecorator => SetMetadata(PUBLIC_ROUTE, true);

/** 仅返回全局守卫核验后注入的身份；不读取调用者提供的用户标识。 */
export const CurrentUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthPrincipal | undefined =>
    context.switchToHttp().getRequest<AuthRequest>().principal,
);
