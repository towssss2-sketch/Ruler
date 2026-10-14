import { HttpException } from '@nestjs/common';

/** 仅用于经过审查的固定业务消息；不得传入底层异常或用户输入。 */
export class BizException extends HttpException {
  constructor(readonly code: number, message: string, readonly httpStatus: number,
    readonly data: { existingCaseId: string } | null = null) {
    super(message, httpStatus);
  }
}
