import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const path = name => fileURLToPath(new URL(`../test-results/${name}`, import.meta.url));
const report = JSON.parse(readFileSync(path('auth-validation.json'), 'utf8'));
const suites = report.testResults.filter(suite => /[/\\](archive\.e2e\.ts|assign\.e2e\.ts|files\.e2e\.ts|file-boundaries\.e2e\.ts|storage-fingerprint\.spec\.ts)$/.test(suite.name));
const tests = suites.flatMap(suite => suite.assertionResults);
const real = suites.filter(suite => suite.name.endsWith('.e2e.ts')).flatMap(suite => suite.assertionResults);
if (suites.length !== 5 || !real.length || !tests.length) throw new Error('缺少文件暂存真实测试，不能生成报告');
const count = status => tests.filter(test => test.status === status).length;
const summary = { total: tests.length, passed: count('passed'), failed: count('failed'),
  notRun: tests.length-count('passed')-count('failed'), realHttpTests: real.length,
  realHttpPassed: real.filter(test => test.status === 'passed').length,
  overallPassed: report.numPassedTests, overallFailed: report.numFailedTests, overallNotRun: report.numPendingTests,
  filePickerUi: 'IMPLEMENTED_DEVICE_NOT_RUN', classificationAssignment: 'MANUAL_IMPLEMENTED_DEVICE_NOT_RUN', realOss: 'NOT_RUN',
  success: report.success && count('passed') === tests.length };
const escape = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const labels = { passed: '通过', failed: '失败', pending: '未运行', todo: '未运行' };
const rows = tests.map(test => `<tr><td>${escape(test.fullName)}</td><td>${labels[test.status] ?? '未运行'}</td></tr>`).join('\n');
writeFileSync(path('ingestion-file-validation.json'), JSON.stringify(summary,null,2));
writeFileSync(path('ingestion-file-acceptance.html'), `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 文件暂存后端验收</title><style>body{font:16px/1.6 system-ui;max-width:1050px;margin:2rem auto;padding:0 1rem;color:#172637}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border:1px solid #ccd4dc;text-align:left}th{background:#eaf1f8}</style>
<h1>阶段 6A2：文件暂存与人工分类归档</h1><p>${summary.success ? '自动化检查通过，待用户验收' : '检查未全部通过，不能验收'}</p>
<p>本轮专项成功 ${summary.passed}，失败 ${summary.failed}，未运行 ${summary.notRun}；真实 HTTP＋PostgreSQL＋Redis＋MinIO 场景 ${summary.realHttpPassed}/${real.length}。全套后端成功 ${report.numPassedTests}，失败 ${report.numFailedTests}，未运行 ${report.numPendingTests}。</p>
<h2>本轮实际行为</h2><ol><li>不选案件也能申请上传，实际文件核验后进入本人待定区；支持既有六种格式，单文件上限 200MiB。</li><li>服务端读取真实字节计算内容指纹，同内容改名不重复计容量；同名不同内容分开保留。重复已忽略文件不自动恢复。</li><li>案件文件和待定文件共用配额及二十张有效上传票据上限；他人不能登记或下载。</li><li>复制、读取、审计失败可重试；过期清理回收未接收副本，保留已接收或忽略原件。</li><li>待定附件可选案件及 11 类分类归档；保留原件并新增一份案件副本，增加同等容量。并发/重试只登记一次，忽略和已删除记录不能隐式重建。</li></ol>
<h2>体验与边界</h2><p>这份报告展示后台真实执行结果。客户端文件选择、暂存和下载已由阶段 6A2B1 接入，界面证据请看客户端报告；6A2B2 已接通 11 类人工分类、案件搜索与指派；真实设备未验证；6A2C 已接通归档去向、进入案件、撤回待定及重新分类；原有案件文件上传和 11 类手动分类保持。尚未提取正文、自动匹配或调用 AI，没有连接真实微信、OSS 或法院平台。</p>
<p>已签发下载链接最长十分钟，不能承诺立刻撤回。忽略或软删除不释放原件容量。OSS 仅离线驱动契约；没有公网测试服务、生产部署或自动合并。你无需改代码或运行命令，可回复“通过”或“不通过＋现象”。</p>
<table><thead><tr><th>实际执行场景</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table></html>`, { mode: 0o600 });
console.log('PASS 中文文件暂存后端验收 HTML 已生成（无正文、签名或凭据）');
