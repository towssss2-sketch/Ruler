import {
  ArgumentsHost, CallHandler, Catch, ExceptionFilter, ExecutionContext,
  HttpException, Injectable, NestInterceptor,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Request, Response } from 'express';
import { Observable, map } from 'rxjs';
import pino from 'pino';
import { BizException } from './biz-exception';

export interface ApiEnvelope<T> {
  code: number;
  message: string;
  data: T;
  traceId: string;
}

export interface TracedRequest extends Request {
  traceId?: string;
}

// 不记录请求正文、URL 查询参数、Authorization、数据库错误或其他敏感内容。
const logger = pino({ base: undefined });

/** 每个请求生成服务端 traceId，避免将不可信请求头写入日志。 */
export function requestTrace(request: TracedRequest, response: Response, next: () => void): void {
  request.traceId = randomUUID();
  response.setHeader('x-trace-id', request.traceId);
  response.once('finish', (): void => { logger.info({ traceId: request.traceId, status: response.statusCode }, '请求完成'); });
  next();
}

@Injectable()
export class ResponseEnvelope implements NestInterceptor<unknown, ApiEnvelope<unknown>> {
  /** 将成功结果封装为统一响应结构。 */
  intercept(context: ExecutionContext, next: CallHandler): Observable<ApiEnvelope<unknown>> {
    const request = context.switchToHttp().getRequest<TracedRequest>();
    return next.handle().pipe(map((data: unknown): ApiEnvelope<unknown> => ({
      code: 0, message: 'ok', data, traceId: request.traceId ?? randomUUID(),
    })));
  }
}

@Catch()
export class SafeExceptionFilter implements ExceptionFilter {
  /** 固定错误消息；不将内部异常、路径或输入数据返回给调用者。 */
  catch(exception: unknown, host: ArgumentsHost): void {
    const request = host.switchToHttp().getRequest<TracedRequest>();
    const response = host.switchToHttp().getResponse<Response>();
    const status = exception instanceof HttpException ? exception.getStatus() : 500;
    const traceId = request.traceId ?? randomUUID();
    logger.warn({ traceId, status }, '请求失败');
    const messages: Record<number, string> = { 400: '输入格式不正确', 401: '身份校验失败', 403: '无访问权限',
      404: '接口不存在', 409: '记录已存在', 429: '请求过于频繁' };
    const message = exception instanceof BizException ? exception.message : messages[status] ?? '服务暂不可用';
    response.status(status).json({ code: exception instanceof BizException ? exception.code : status,
      message, data: exception instanceof BizException ? exception.data : null, traceId });
  }
}
