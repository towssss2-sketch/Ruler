import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// 仅渲染固定测试标题/状态/汇总；禁止包含请求内容、断言值、失败堆栈或任何凭据。
const jsonPath = fileURLToPath(new URL('../test-results/auth-validation.json', import.meta.url));
const htmlPath = fileURLToPath(new URL('../test-results/auth-acceptance.html', import.meta.url));
const report = JSON.parse(readFileSync(jsonPath, 'utf8'));
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const statusText = { passed: '通过', failed: '失败', pending: '未运行', todo: '未运行' };
const rows = report.testResults.flatMap(suite => suite.assertionResults.map(test =>
  `<tr><td>${escape(test.fullName)}</td><td>${escape(statusText[test.status] ?? '未运行')}</td></tr>`)).join('\n');
const status = report.success ? '自动检查通过，待用户验收' : '检查未通过，不能验收';
writeFileSync(htmlPath, `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 阶段2–3自动验收证据</title><style>body{font:16px/1.6 system-ui;max-width:1000px;margin:2rem auto;padding:0 1rem;color:#172637}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border:1px solid #ccd4dc;text-align:left}th{background:#eaf1f8}</style>
<h1>阶段2–3：鉴权与案件管理自动验收证据</h1><p>${escape(status)}</p>
<p>成功 ${report.numPassedTests}；失败 ${report.numFailedTests}；未运行 ${report.numPendingTests}。</p>
<p>使用独立测试数据库与虚构邮箱。验证码只在测试进程内传递，没有真实邮件、法院、支付或 AI 调用。全局覆盖率门槛保持 80%。</p>
<p>本报告记录鉴权与整体回归结果，客户端尚无业务界面。文件业务的真实 HTTP 和 MinIO 验证见独立 document-acceptance.html；鉴权测试中的任务记录仅用于测试准备，不表示任务模块已完成。没有生产部署或自动合并。</p>
<table><thead><tr><th>已实际执行的中文场景</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table></html>`, { mode: 0o600 });
console.log('PASS 中文鉴权验收 HTML 已生成（无凭据/断言值/堆栈）');
