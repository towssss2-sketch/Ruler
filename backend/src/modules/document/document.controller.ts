import { Body, Controller, Delete, Get, Header, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthPrincipal, CurrentUser } from '../auth/auth-decorators';
import { CaseAccessGuard, ScopedRequest } from '../case/case-access.guard';
import { dto } from '../case/case-input';
import { DocumentQuery, PresignInput, RegisterInput, VisibilityInput } from './document-input';
import { DocumentView } from './document-policy';
import { DocumentUploadService, UploadOffer } from './document-upload.service';
import { DocumentRegisterService } from './document-register.service';
import { DocumentReadService, DocumentPage } from './document-read.service';
import { DocumentWriteService } from './document-write.service';
import { SignedTransfer } from './storage/storage.service';

@ApiTags('案件文件') @ApiBearerAuth() @UseGuards(CaseAccessGuard) @Controller()
export class DocumentController {
  constructor(private readonly uploads: DocumentUploadService, private readonly registration: DocumentRegisterService,
    private readonly read: DocumentReadService, private readonly write: DocumentWriteService) {}

  /** 校验上传 DTO 后生成临时对象签名，不接受任意存储路径。 */
  @Post('cases/:caseId/documents/presign') @Header('Cache-Control', 'private, no-store')
  @ApiOperation({ summary: '申请上传票据与短效签名；previousDocumentId 指定新版本' })
  presign(@CurrentUser() user: AuthPrincipal, @Param('caseId') caseId: string, @Body() body: PresignInput): Promise<UploadOffer> {
    return this.uploads.presign(user.userId, caseId, dto(PresignInput, body));
  }

  /** 只转发已验证票据及分类，由服务核验对象、配额和事务登记。 */
  @Post('cases/:caseId/documents') @ApiOperation({ summary: '上传完成后登记文件；同票据可安全重试' })
  register(@CurrentUser() user: AuthPrincipal, @Param('caseId') caseId: string, @Body() body: RegisterInput): Promise<DocumentView> {
    return this.registration.register(user.userId, caseId, dto(RegisterInput, body));
  }

  /** 分页查询当前版本，includeHistory=true 可看保留历史。 */
  @Get('cases/:caseId/documents') @ApiOperation({ summary: '按分类查询文件，默认仅当前版本' })
  list(@CurrentUser() user: AuthPrincipal, @Param('caseId') caseId: string, @Query() query: unknown): Promise<DocumentPage> {
    return this.read.list(user.userId, caseId, dto(DocumentQuery, query));
  }

  /** 守卫反查父案件后生成短效下载凭据。 */
  @Get('documents/:documentId/download') @Header('Cache-Control', 'private, no-store')
  @ApiOperation({ summary: '鉴权后签发至多十分钟的下载链接' })
  download(@CurrentUser() user: AuthPrincipal, @Param('documentId') id: string, @Req() request: ScopedRequest): Promise<SignedTransfer> {
    return this.read.download(user.userId, request.resourceScope!.caseId, id);
  }

  /** 校验布尔值并审计客户可见性变化。 */
  @Patch('documents/:documentId/client-visibility') @ApiOperation({ summary: '设置客户可见标记（门户尚未上线）' })
  visibility(@CurrentUser() user: AuthPrincipal, @Param('documentId') id: string, @Req() request: ScopedRequest,
    @Body() body: VisibilityInput): Promise<DocumentView> {
    return this.write.visibility(user.userId, request.resourceScope!.caseId, id, dto(VisibilityInput, body).isClientVisible);
  }

  /** 软删除指定版本，保留底层文件与配额占用。 */
  @Delete('documents/:documentId') @ApiOperation({ summary: '软删除文件版本，保留审计及对象' })
  remove(@CurrentUser() user: AuthPrincipal, @Param('documentId') id: string, @Req() request: ScopedRequest): Promise<{ deleted: true }> {
    return this.write.remove(user.userId, request.resourceScope!.caseId, id);
  }
}
