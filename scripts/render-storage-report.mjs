import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// 只渲染实际 Jest 标题、状态与数量；不把对象内容、签名 URL、SDK 错误或断言值放入报告。
const report = JSON.parse(readFileSync(fileURLToPath(new URL('../test-results/auth-validation.json', import.meta.url)), 'utf8'));
const suites = report.testResults.filter(suite => /[/\\]test[/\\](storage[/\\]|storage-[^/\\]+\.spec\.ts)/.test(suite.name));
const tests = suites.flatMap(suite => suite.assertionResults);
const realTests = suites.filter(suite => suite.name.endsWith('minio.e2e.ts')).flatMap(suite => suite.assertionResults);
if (!tests.length || !realTests.length) throw new Error('缺少真实存储测试结果，不能生成验收报告');
const passed = tests.filter(test => test.status === 'passed').length;
const failed = tests.filter(test => test.status === 'failed').length;
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const labels = { passed: '通过', failed: '失败', pending: '未运行', todo: '未运行' };
const rows = tests.map(test => `<tr><td>${escape(test.fullName)}</td><td>${labels[test.status] ?? '未运行'}</td></tr>`).join('\n');
const summary = { passed, failed, notRun: tests.length-passed-failed, total: tests.length,
  realMinioTests: realTests.length, realMinioPassed: realTests.filter(test => test.status === 'passed').length,
  overallPassed: report.numPassedTests, overallFailed: report.numFailedTests, overallNotRun: report.numPendingTests,
  realOss: 'NOT_RUN', documentApi: 'SEE_DOCUMENT_REPORT', success: report.success && passed === tests.length };
writeFileSync(fileURLToPath(new URL('../test-results/storage-validation.json', import.meta.url)), JSON.stringify(summary, null, 2));
writeFileSync(fileURLToPath(new URL('../test-results/storage-acceptance.html', import.meta.url)), `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 阶段4A存储基座验收</title><style>body{font:16px/1.6 system-ui;max-width:1050px;margin:2rem auto;padding:0 1rem;color:#172637}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border:1px solid #ccd4dc;text-align:left}th{background:#eaf1f8}</style>
<h1>阶段4A：存储驱动与短效签名</h1><p>${summary.success ? '自动化检查通过，待用户验收' : '检查未全部通过，不能验收'}</p>
<p>存储专项：成功 ${passed}，失败 ${failed}，未运行 ${summary.notRun}；其中真实 MinIO 场景 ${summary.realMinioPassed}/${realTests.length}。全套后端回归成功 ${report.numPassedTests}，失败 ${report.numFailedTests}，未运行 ${report.numPendingTests}。</p>
<h2>已实际验证</h2><ol><li>虚构文件通过短效签名直接上传到本机私有 MinIO，并下载核对内容。</li>
<li>中文文件名、文件大小和类型正确；复制保持内容一致；删除后不可读取。</li>
<li>无签名、签名篡改、过期、长度或内容校验不符会被拒绝。</li>
<li>连接、权限或桶故障明确失败，不伪装成“没有文件”。</li></ol>
<h2>尚未交付的内容</h2><p>OSS 采用官方 SDK 的 V4 离线签名和适配器测试，没有连接真实阿里云，没有证明真实 OSS 读写可用。</p>
<p>本报告只检查阶段4A的存储驱动。案件文件接口、文档登记、配额、版本、权限与上传票据的阶段4B结果见独立的 document-acceptance.html。安装包仍是欢迎页，没有文件上传按钮。签名是到期前有效的访问凭据，不能放入日志或截图。</p>
<p>MD5 用于存储协议的传输校验，不代表文件安全、身份认证或防碰撞证明；200 MiB 边界已验证入参和签名约束，未实际传输 200 MiB 大文件。</p>
<p>你只需查看中文场景，有空再反馈“通过”或“不通过＋现象”。未自动合并，未生产部署。</p>
<table><thead><tr><th>真实执行的场景（离线与实际 MinIO 已在标题区分）</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table></html>`, { mode: 0o600 });
console.log('PASS 中文存储验收 HTML 已生成（无签名 URL、对象正文或凭据）');
