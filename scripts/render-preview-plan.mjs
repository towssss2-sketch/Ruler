import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { evaluatePlan } from './preview-plan.mjs';
import { probeCurrentStorage } from './preview-probe.mjs';
const target = name => new URL(`../test-results/${name}`, import.meta.url);
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/** 生成本轮审阅材料；探针或输入错误以失败退出，不沿用旧报告、不回显原始错误。 */
async function main() {
  mkdirSync(target(''), { recursive: true });
  const report = { generatedAt: new Date().toISOString(), status: 'FAILED', configurationValid: false };
  writeReport(report);
  try {
    Object.assign(report, evaluatePlan(JSON.parse(readFileSync(new URL('../infra/preview/plan.json', import.meta.url), 'utf8'))));
    if (!report.configurationValid) throw new Error('invalid');
    report.storageProbe = await probeCurrentStorage();
    writeReport(report);
    console.log('PASS 方案格式与离线探针已执行；公网体验 BLOCKED，未部署、未联网检查');
  } catch {
    report.status = 'FAILED';
    writeReport(report);
    console.error('FAIL 方案报告生成失败；请检查依赖、后端构建与方案格式，未输出输入或底层错误');
    process.exitCode = 1;
  }
}

/** 输出固定中文说明与脱敏检查结果；不包含候选地址、账号、凭据或下载签名。 */
function writeReport(report) {
  writeFileSync(target('preview-plan.json'), JSON.stringify(report, null, 2));
  writeFileSync(target('preview-plan.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>RULER 测试环境审阅方案</title>
<style>body{font:16px/1.8 system-ui;max-width:900px;margin:2rem auto;padding:1rem}li{margin:.5rem 0}</style>
<h1>手机与 Windows 测试环境方案</h1><p>本次状态：${escape(report.status)}。仅作审阅，没有购买或部署。</p>
<p>建议：阿里云香港临时测试机，2 核 / 4 GiB 内存 / 60 GiB 磁盘，2 个虚构账号。
测试 7 天，关闭入口后再保留 7 天供复核；清理和释放资源前再次核对授权。</p>
<p>建议云资源合计上限 300 元/月，域名首年上限 100 元；首期合计上限 400 元。
这是预算建议，不是实时报价；包含流量、磁盘、证书等后再询价确认，不自动续费。</p>
<p>地域仅为建议，涉及跨境位置；只放虚构资料。正式大陆环境及备案另行设计，不由本方案替代。</p>
<h2>当前还缺什么</h2><ul>${(report.issues ?? ['报告未完成']).map(text => `<li>${escape(text)}</li>`).join('')}</ul>
<h2>实际代码检查</h2><p>当前后端拒绝非本机 MinIO 地址：${escape(report.storageProbe?.publicEndpointRejected ?? 'NOT_RUN')}；
离线生成的文件链接指向本机：${escape(report.storageProbe?.signedOriginIsLoopback ?? 'NOT_RUN')}。
探针执行实际编译代码，使用虚构签名凭据，不连接服务器。这两项说明当前代码仍需适配。</p>
<p>地址格式：${escape(report.endpointFormat ?? 'NOT_RUN')}。格式合格不能证明域名归属、DNS、TLS 或服务可达。
自动化测试数量请看同包 preview-tests.tap；此页状态不代替测试结果。</p>
<h2>开通顺序与体验交付</h2><ol><li>审阅资源、地域、预算和虚构数据范围。</li>
<li>取得完整当前报价和明确购买、测试部署授权；在你名下开通资源。</li>
<li>工程师完成 HTTPS、文件地址、账号交付、入口隔离和安全检查，再部署隔离测试环境。</li>
<li>交付已配置地址的 APK / Windows ZIP 和安全渠道中的临时账号，无需你改代码。</li>
<li>登录→建虚构案件→上传测试 PDF→新增任务→重登→上传新版本→下载核对，另核对第二账号无法查看。</li></ol>
<p>当前可审阅方案；客户端公网登录、系统窗口和真机体验均未验证。完整资源、职责、撤回及到期安排见同包《客户端测试环境方案.md》。
你只需回复“方案通过”或指出调整项；方案通过也不直接触发购买、部署或合并。</p></html>`);
}
await main();
