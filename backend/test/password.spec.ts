import { PasswordService } from '../src/modules/auth/password.service';
import { loginInput, parseInput, registerInput } from '../src/modules/auth/auth-input';
import { OwnerOnlyPolicy } from '../src/modules/case/case-policy';

describe('密码哈希与严格输入', (): void => {
  const service = new PasswordService();
  const password = 'Fictional-Test-Password-Only!';
  it('随机盐、不可逆保存、正确密码核验及错误密码拒绝', async (): Promise<void> => {
    const first = await service.hash(password);
    const second = await service.hash(password);
    expect(first).not.toBe(second);
    expect(first).not.toContain(password);
    expect(await service.verify(password, first)).toBe(true);
    expect(await service.verify('wrong', first)).toBe(false);
    expect(await service.verify(password, 'invalid-format')).toBe(false);
  });
  it('规范化邮箱并拒绝额外字段、过短密码或非法验证码', (): void => {
    const valid = { email: '  FICTIONAL@example.invalid ', password };
    expect(parseInput(loginInput, valid).email).toBe('fictional@example.invalid');
    expect((): void => { parseInput(loginInput, { ...valid, ownerId: 'forged' }); }).toThrow();
    expect((): void => { parseInput(loginInput, { ...valid, password: 'short' }); }).toThrow();
    expect((): void => { parseInput(registerInput, { ...valid, name: '虚构律师', code: 'bad' }); }).toThrow();
  });
  it('本期仅 OWNER 允许操作，其他角色的协作接口留待阶段 9', (): void => {
    const policy = new OwnerOnlyPolicy();
    expect(policy.permits('OWNER', 'GET')).toBe(true);
    expect(policy.permits('EDITOR', 'POST')).toBe(false);
    expect(policy.permits('VIEWER', 'GET')).toBe(false);
    expect(policy.permits(undefined, 'GET')).toBe(false);
  });
});
