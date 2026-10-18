import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
const target = name => new URL(`../test-results/${name}`, import.meta.url);
const restricted = process.argv.includes('--restricted');
const prefix = restricted ? 'client-restricted' : 'client-https';
const data = JSON.parse(readFileSync(target(`${prefix}-validation.json`), 'utf8'));
assert.equal(data.transport, 'REAL_DART_DIO_NEST_POSTGRES_REDIS_MINIO');
assert.equal(data.tls, 'LOCAL_TRUSTED_CERTIFICATE');
assert.equal(data.passed, 10);
assert.equal(data.failed, 0);
assert.equal(data.skipped, 0);
assert.equal(data.scenarios.length, data.passed);
assert.deepEqual(data.storageIngress, { separateHttps: true, jwtOrCookieObserved: false });
assert.equal(data.runtimeProfile, restricted ? 'restricted-local' : 'development');
if (restricted) {
  assert.equal(data.serviceRestarted, true);
  assert.equal(data.boundaryChecks.length, 12);
  assert.equal(new Set(data.boundaryChecks).size, 12);
}
const escape = text => String(text).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
writeFileSync(target(`${prefix}-acceptance.html`), `<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>RULER 本机 HTTPS 客户端联调</title>
<style>body{font:16px/1.8 system-ui;max-width:900px;margin:2rem auto;padding:1rem}li{margin:.6rem 0}</style>
<h1>真实客户端双 HTTPS 入口联调</h1><p>10 项通过，0 失败，0 跳过。</p>
${restricted ? `<h2>本机隔离模式：额外 12 项入口检查通过</h2>
<p>先用正常验证码注册流程创建两个随机虚构账号，关闭准备服务，重新启动隔离模式。
以下入口在客户端业务联调前后均返回 404；没有临时打开注册或创建公开取码后门。</p>
<ol>${data.boundaryChecks.map(name => `<li>通过：${escape(name)}</li>`).join('')}</ol>
<p>已有账号仍可完成下列业务。这里验证的是本机入口关闭，不代表完整公共测试环境已部署；账号发放、到期吊销和公网入口仍未交付。</p>` : ''}
<p>实际应用的 Dart/Dio 网络层通过 HTTPS 连接真实 Nest API，使用另一个 HTTPS 文件入口上传下载，
后端对象管理连接本机私有 MinIO。PostgreSQL、Redis、MinIO 均实际参与，虚构账号和数据在结束后清理。</p>
<ol>${data.scenarios.map(name => `<li>通过：${escape(name)}</li>`).join('')}</ol>
<p>新增的证书场景覆盖 API 和文件两个入口：默认客户端都拒绝本次未受信任的证书。
随后只在联调工具的局部测试区显式信任本次临时证书，完成其余九项业务场景。
没有关闭证书或主机校验，没有安装系统信任根，测试证书及信任逻辑不进入安装包。
文件入口实际收到 PUT/GET，未收到登录 Authorization 或 Cookie 头。</p>
<p>这不是公网证书或手机真机验证。两个入口均绑定本机随机端口；文件 HTTPS 转发器仅供测试，不能作为部署网关。
真实设备、公共域名、受信任的公开证书、受控账号交付及部署仍未完成，默认安装包仍不能公网登录。
你可以直接看此报告，无需改配置或运行命令。没有购买、部署或自动合并。</p></html>`);
console.log(`PASS 已生成中文${restricted ? '隔离模式' : '双 HTTPS'}真实客户端联调报告`);
