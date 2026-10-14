import { BadRequestException, Injectable } from '@nestjs/common';

/** 虚构邮箱的内存投递适配器；没有网络发送或 HTTP 取码接口。 */
@Injectable()
export class DevelopmentMailbox {
  private readonly messages = new Map<string, { code: string; expires: number }>();

  /** 仅接收保留的 example.invalid 测试域，真实邮箱须另行接入批准后的驱动。 */
  async send(email: string, code: string): Promise<void> {
    if (!email.endsWith('@example.invalid')) throw new BadRequestException('开发环境仅接受虚构测试邮箱');
    for (const [key, value] of this.messages) if (value.expires < Date.now()) this.messages.delete(key);
    if (this.messages.size >= 1000) throw new BadRequestException('测试邮箱暂不可用');
    this.messages.set(email, { code, expires: Date.now() + 600_000 });
  }

  /** 只供进程内自动测试读取，读取后移除；不得注册为公网端点。 */
  take(email: string): string | undefined {
    const message = this.messages.get(email);
    this.messages.delete(email);
    return message && message.expires > Date.now() ? message.code : undefined;
  }
}
