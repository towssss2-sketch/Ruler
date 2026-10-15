import { DocumentCategory } from '@prisma/client';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsEnum, IsIn, IsInt, IsString, IsUUID, Length, Matches, Max, Min, ValidateIf } from 'class-validator';
import { PageInput } from '../case/case-input';
import { MAX_FILE_BYTES } from './storage/storage-policy';

/** 新文件或新版本的上传申请；不接收客户端对象键、所有者或版本号。 */
export class PresignInput {
  @ApiProperty({ description: '文件名，后端安全化处理；仅允许六类文件的扩展名' })
  @IsString() @Length(1, 512) fileName!: string;
  @ApiProperty({ description: 'application/pdf、application/msword、DOCX MIME、image/jpeg、image/png 或 video/mp4' })
  @IsString() @Length(1, 128) mimeType!: string;
  @ApiProperty({ minimum: 1, maximum: MAX_FILE_BYTES, description: '实际文件字节数' })
  @IsInt() @Min(1) @Max(MAX_FILE_BYTES) sizeBytes!: number;
  @ApiProperty({ description: '文件协议 MD5 校验值，标准 Base64；不是用户身份或文件安全证明' })
  @IsString() @Matches(/^[A-Za-z0-9+/]{22}==$/) contentMd5!: string;
  @ApiPropertyOptional({ format: 'uuid', description: '同案件已有未删除文件 ID；省略创建独立文件' })
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsUUID() previousDocumentId?: string;
}
/** 登记只接受当前用户的票据与分类，元数据从票据和对象存储取得。 */
export class RegisterInput {
  @ApiProperty({ format: 'uuid', description: '上传签名接口返回的 uploadId' })
  @IsUUID() uploadId!: string;
  @ApiProperty({ enum: DocumentCategory })
  @IsEnum(DocumentCategory) category!: DocumentCategory;
}
export class VisibilityInput {
  @ApiProperty({ description: '仅保存可见标记；客户门户尚未开放' })
  @IsBoolean() isClientVisible!: boolean;
}
export class DocumentQuery extends PageInput {
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsEnum(DocumentCategory) category?: DocumentCategory;
  @IsIn(['true', 'false']) includeHistory = 'false';
}
