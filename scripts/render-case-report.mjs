import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// 来自本次 Jest 结果，只渲染静态测试标题和状态，不输出输入、断言值或堆栈。
const report = JSON.parse(readFileSync(fileURLToPath(new URL('../test-results/auth-validation.json', import.meta.url)), 'utf8'));
const suites = report.testResults.filter(suite => /[/\\]test[/\\](case[/\\]|case-[^/\\]+\.spec\.ts)/.test(suite.name));
const tests = suites.flatMap(suite => suite.assertionResults);
if (tests.length === 0) throw new Error('没有实际案件测试结果，不能生成验收报告');
const passed = tests.filter(test => test.status === 'passed').length;
const failed = tests.filter(test => test.status === 'failed').length;
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const labels = { passed: '通过', failed: '失败', pending: '未运行', todo: '未运行' };
const rows = tests.map(test => `<tr><td>${escape(test.fullName)}</td><td>${labels[test.status] ?? '未运行'}</td></tr>`).join('\n');
const summary = { passed, failed, notRun: tests.length - passed - failed, total: tests.length,
  overallPassed: report.numPassedTests, overallFailed: report.numFailedTests, overallNotRun: report.numPendingTests,
  success: report.success && failed === 0 && passed === tests.length };
writeFileSync(fileURLToPath(new URL('../test-results/case-validation.json', import.meta.url)), JSON.stringify(summary, null, 2));
writeFileSync(fileURLToPath(new URL('../test-results/case-acceptance.html', import.meta.url)), `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 阶段3案件管理验收</title><style>body{font:16px/1.6 system-ui;max-width:1050px;margin:2rem auto;padding:0 1rem;color:#172637}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border:1px solid #ccd4dc;text-align:left}th{background:#eaf1f8}strong{color:#155c45}</style>
<h1>阶段3：案件管理</h1><p><strong>${summary.success ? '自动化检查通过，待用户验收' : '检查未全部通过，不能验收'}</strong></p>
<p>案件专项：成功 ${passed}，失败 ${failed}，未运行 ${summary.notRun}。含历史回归的全套后端检查：成功 ${report.numPassedTests}，失败 ${report.numFailedTests}，未运行 ${report.numPendingTests}。</p>
<h2>已验证的用户行为</h2><ol><li>虚构账号登录后新建案件、填写当事人并保存。</li>
<li>按案号、姓名、案由查找，按法院、阶段、状态筛选；6A3C 新增完整案号精确条件，与其他条件取交集，同号多法院全部分页返回；不会看到其他账号或已删除案件。</li>
<li>修改信息、删除普通案件；重复案号提示打开已有案件，数据库失败时整次保存撤销。</li>
<li>检查本人的历史案件，列出姓名相似的候选案件供人工复核。</li></ol>
<p>联系方式、身份证文本、地址、书记员电话和备注以密文保存；测试只使用虚构数据。</p>
<h2>体验与限制</h2><p>这是后端阶段的自动验收证据。客户端已接入案件管理和正文候选案号查找，界面与截图请看 ruler-client-experience 产物；默认包可体验虚构流程，公共测试服务及真机验证仍未交付。</p>
<p>存在法定期间记录时暂不允许删除案件，可标记结案但不会删除期间记录；其他用户归集资料也受到删除保护。协作组预留为空，完整协作权限在阶段9实现。冲突候选不是法律判断。生产密钥轮换、真实设备及生产部署未执行。</p>
<p>你可先看下方中文场景，稍后再反馈“通过”或“不通过＋现象”。继续开发不代表验收通过，所有 PR 保持未合并。</p>
<h2>本次真实测试结果</h2><table><thead><tr><th>场景</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table></html>`, { mode: 0o600 });
console.log('PASS 中文案件验收 HTML 已生成（无凭据/断言值/堆栈）');
