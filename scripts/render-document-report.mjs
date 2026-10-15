import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const report = JSON.parse(readFileSync(fileURLToPath(new URL('../test-results/auth-validation.json', import.meta.url)), 'utf8'));
const suites = report.testResults.filter(suite => /[/\\]test[/\\](document[/\\]|document-[^/\\]+\.spec\.ts)/.test(suite.name));
const tests = suites.flatMap(suite => suite.assertionResults);
const http = suites.filter(suite => suite.name.endsWith('.e2e.ts')).flatMap(suite => suite.assertionResults);
if (!tests.length || !http.length) throw new Error('没有实际文件接口测试结果，不能生成验收报告');
const passed = tests.filter(test => test.status === 'passed').length;
const failed = tests.filter(test => test.status === 'failed').length;
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const labels = { passed: '通过', failed: '失败', pending: '未运行', todo: '未运行' };
const rows = tests.map(test => `<tr><td>${escape(test.fullName)}</td><td>${labels[test.status] ?? '未运行'}</td></tr>`).join('\n');
const summary = { total: tests.length, passed, failed, notRun: tests.length - passed - failed,
  realHttpTests: http.length, realHttpPassed: http.filter(test => test.status === 'passed').length,
  overallPassed: report.numPassedTests, overallFailed: report.numFailedTests, overallNotRun: report.numPendingTests,
  realOss: 'NOT_RUN', collaboration: 'OWNER_ONLY', clientUploadUi: 'NOT_IMPLEMENTED',
  success: report.success && passed === tests.length };
writeFileSync(fileURLToPath(new URL('../test-results/document-validation.json', import.meta.url)), JSON.stringify(summary, null, 2));
writeFileSync(fileURLToPath(new URL('../test-results/document-acceptance.html', import.meta.url)), `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 阶段4B文件业务验收</title><style>body{font:16px/1.6 system-ui;max-width:1050px;margin:2rem auto;padding:0 1rem;color:#172637}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border:1px solid #ccd4dc;text-align:left}th{background:#eaf1f8}</style>
<h1>阶段4B：案件文件业务</h1><p>${summary.success ? '自动化检查通过，待用户验收' : '检查未全部通过，不能验收'}</p>
<p>文件业务专项：成功 ${passed}，失败 ${failed}，未运行 ${summary.notRun}；真实 HTTP 场景 ${summary.realHttpPassed}/${http.length}。全套后端回归成功 ${report.numPassedTests}，失败 ${report.numFailedTests}，未运行 ${report.numPendingTests}。</p>
<h2>你可以核对的结果</h2><ol><li>虚构账号注册登录后新建案件，通过签名上传到本机私有 MinIO，再登记、列出、下载并核对内容。</li>
<li>别人的文件、他案票据和来源伪造均被拒绝；同票据重试不会重复扣容量。</li>
<li>同时上传不同案件的文件也不能突破同一主办律师配额；新旧版本乱序完成仍保持正确当前版本。</li>
<li>可见性变化与删除有审计；软删除保留文件和已用容量，已发下载链接在到期前仍有效。</li>
<li>复制或数据库失败可重试，过期临时对象可回收；已登记正式文件不会被清理任务物理删除。</li></ol>
<h2>本次没有交付的内容</h2><p>客户端仍是欢迎页，没有上传按钮。协作角色暂不开放；真实 OSS、短信/邮箱/法院渠道、真实设备安装和 200 MiB 大文件压力测试均未运行。归集来源只验证内部接口契约，不代表归集管道已完成。</p>
<p>报告仅展示真实测试的标题和状态，不包含签名地址、文件正文或凭据。测试使用虚构材料；没有自动合并或生产部署。你有空时只需反馈“通过”或“不通过＋现象”。</p>
<table><thead><tr><th>实际执行的中文场景</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table></html>`, { mode: 0o600 });
console.log('PASS 中文文件业务验收 HTML 已生成（不含正文、签名或凭据）');
