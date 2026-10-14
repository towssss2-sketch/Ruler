import { randomInt } from 'node:crypto';
import { CreateCaseInput } from '../../src/modules/case/case-input';
import { request } from '../auth/fixture';

/** 生成仅用于隔离测试库的虚构案件，不使用真实联系方式。 */
export function input(overrides: Partial<CreateCaseInput> = {}): CreateCaseInput {
  return { caseNo: `(2026)浙0302民初${randomInt(1, 2000000000)}号`, cause: '虚构合同纠纷', court: '虚构测试法院',
    parties: [{ role: 'PLAINTIFF', name: '虚构东方甲乙丙丁', phone: 'fictional-phone',
      idCard: 'fictional-id-card', address: '虚构地址' }], notes: '虚构案情备注',
    clerkPhone: 'fictional-clerk-phone', fee: '123456789012.34', ...overrides };
}

/** 从真实 HTTP 创建案件，只检查状态避免输出认证凭据。 */
export async function newCase(access: string, values: CreateCaseInput = input()): Promise<string> {
  const reply = await request('/cases', values, access);
  expect(reply.status).toBe(201);
  return reply.data.id as string;
}
