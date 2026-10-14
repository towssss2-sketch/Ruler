import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { AuthRequest } from '../auth/auth-decorators';
import { AuthorizedScope, CaseAccessService } from './case-access.service';

export interface ScopedRequest extends AuthRequest { resourceScope?: AuthorizedScope }

@Injectable()
export class CaseAccessGuard implements CanActivate {
  constructor(private readonly access: CaseAccessService) {}

  /** 全局身份守卫之后核验路径中全部资源，每次查库并注入已授权范围。 */
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<ScopedRequest>();
    if (!request.principal) throw new UnauthorizedException();
    const { caseId, documentId, taskId } = request.params;
    request.resourceScope = await this.access.authorize(request.principal.userId,
      { caseId, documentId, taskId }, request.method);
    return true;
  }
}
