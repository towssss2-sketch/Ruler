import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const report = JSON.parse(readFileSync(fileURLToPath(new URL('../test-results/auth-validation.json', import.meta.url)), 'utf8'));
const suites = report.testResults.filter(suite => /[/\\]test[/\\](task[/\\]|task-[^/\\]+\.spec\.ts)/.test(suite.name));
const tests = suites.flatMap(suite => suite.assertionResults);
const real = suites.filter(suite => suite.name.endsWith('.e2e.ts')).flatMap(suite => suite.assertionResults);
if (!tests.length || !real.length) throw new Error('缺少真实任务测试，不能生成验收报告');
const passed = tests.filter(test => test.status === 'passed').length;
const failed = tests.filter(test => test.status === 'failed').length;
const summary = { total: tests.length, passed, failed, notRun: tests.length-passed-failed,
  realHttpTests: real.length, realHttpPassed: real.filter(test => test.status === 'passed').length,
  overallPassed: report.numPassedTests, overallFailed: report.numFailedTests, overallNotRun: report.numPendingTests,
  deadlineCalculation: 'NOT_IMPLEMENTED', reminders: 'NOT_IMPLEMENTED', clientUi: 'NOT_IMPLEMENTED',
  success: report.success && passed === tests.length };
const escape = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const labels = { passed: '通过', failed: '失败', pending: '未运行', todo: '未运行' };
const rows = tests.map(test => `<tr><td>${escape(test.fullName)}</td><td>${labels[test.status] ?? '未运行'}</td></tr>`).join('\n');
writeFileSync(fileURLToPath(new URL('../test-results/task-validation.json', import.meta.url)), JSON.stringify(summary,null,2));
writeFileSync(fileURLToPath(new URL('../test-results/task-acceptance.html', import.meta.url)), `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 阶段5A常规任务验收</title><style>body{font:16px/1.6 system-ui;max-width:1050px;margin:2rem auto;padding:0 1rem;color:#172637}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border:1px solid #ccd4dc;text-align:left}th{background:#eaf1f8}</style>
<h1>阶段5A：常规任务</h1><p>${summary.success ? '自动化检查通过，待用户验收' : '检查未全部通过，不能验收'}</p>
<p>任务专项：成功 ${passed}，失败 ${failed}，未运行 ${summary.notRun}；真实 HTTP 场景 ${summary.realHttpPassed}/${real.length}。全套后端成功 ${report.numPassedTests}，失败 ${report.numFailedTests}，未运行 ${report.numPendingTests}。</p>
<h2>实际验证的行为</h2><ol><li>本人案件内手动新建、编辑、完成、恢复待办与软删除；描述加密存储，写操作有审计。</li><li>按来源和状态筛选、分页；今日汇总按北京时间，法定期间优先、逾期其次、今日到期随后。</li><li>未登录、他人和未开放的协作角色被拒绝；未知来源、非法日期和伪造确认信息被拒绝。</li><li>法定期间任务不能删除，普通编辑不能修改其规则和日期。窗口测试使用明确虚构、在数据库准备的已确认记录，不代表已实现律师确认流程。</li></ol>
<h2>本次尚未交付</h2><p>法定期间计算、律师确认接口、定时提醒和去重留阶段5B；协作权限留阶段9。客户端仍是欢迎页，无任务入口。未调用真实法院、短信、AI 或支付，没有生产部署和自动合并。</p>
<p>你无需读代码或运行命令，有空再回复“通过”或“不通过＋现象”。报告只展示测试标题与状态，不包含任务描述、凭据和签名。</p>
<table><thead><tr><th>实际执行场景</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table></html>`, { mode: 0o600 });
console.log('PASS 中文常规任务验收 HTML 已生成（无描述、签名或凭据）');
