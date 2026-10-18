import assert from 'node:assert/strict';

/** 对运行中的真实隔离服务检查入口；只返回固定中文标签，不记录响应或凭据。 */
export async function checkRestrictedEntries(send) {
  const checks = [
    ['注册入口关闭', '/auth/register', 'POST'],
    ['验证码入口关闭', '/auth/verification-code', 'POST'],
    ['注册大小写路径拒绝', '/AUTH/REGISTER', 'POST'],
    ['注册尾斜杠路径拒绝', '/auth/register/', 'POST'],
    ['验证码查询参数不能切换模式', '/auth/verification-code?mode=development', 'POST'],
    ['编码路径不能打开注册', '/auth/%72egister', 'POST'],
    ['其他请求方法不能打开注册', '/auth/register', 'GET'],
    ['文档首页关闭', '/docs', 'GET'],
    ['文档尾斜杠关闭', '/docs/', 'GET'],
    ['文档 JSON 关闭', '/docs-json', 'GET'],
    ['文档 YAML 关闭', '/docs-yaml', 'GET'],
    ['文档脚本关闭', '/docs/swagger-ui-init.js', 'GET'],
  ];
  for (const [, path, method] of checks) assert.equal((await send(path, method)).status, 404);
  return checks.map(([name]) => name);
}
