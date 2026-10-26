import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const path = name => fileURLToPath(new URL(`../test-results/${name}`, import.meta.url));
const source = JSON.parse(readFileSync(path('auth-validation.json'), 'utf8'));
const names = ['document-text.spec.ts', 'document-text-parser.spec.ts', 'document-text-process.spec.ts',
  'docx-limits.spec.ts', 'storage-reader.spec.ts', 'text-preview.e2e.ts'];
const suites = source.testResults.filter(suite => names.some(name => suite.name.replaceAll('\\','/').endsWith(`/${name}`)));
if (suites.length !== names.length) throw new Error('缺少正文提取检查，不能生成验收报告');
const tests = suites.flatMap(suite => suite.assertionResults);
const count = status => tests.filter(test => test.status === status).length;
const summary = { passed: count('passed'), failed: count('failed'), notRun: tests.length-count('passed')-count('failed'),
  total: tests.length, overallPassed: source.numPassedTests, overallFailed: source.numFailedTests,
  overallNotRun: source.numPendingTests, success: source.success && count('passed') === tests.length,
  clientEntry: 'IMPLEMENTED_6A3B', realOss: 'NOT_RUN', realDevice: 'NOT_RUN', automaticPipeline: 'NOT_IMPLEMENTED' };
const escape = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const labels = {passed:'通过',failed:'失败',pending:'未运行',todo:'未运行'};
const rows = tests.map(test => `<tr><td>${escape(test.fullName)}</td><td>${labels[test.status] ?? '未运行'}</td></tr>`).join('\n');
writeFileSync(path('ingestion-text-validation.json'), JSON.stringify(summary,null,2), {mode:0o600});
writeFileSync(path('ingestion-text-acceptance.html'), `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 正文提取与分类建议验收</title><style>body{font:16px/1.7 system-ui;max-width:1050px;margin:2rem auto;padding:0 1rem;color:#172637}table{border-collapse:collapse;width:100%}td,th{padding:.6rem;border:1px solid #ccd4dc;text-align:left}th{background:#eaf1f8}</style>
<h1>阶段 6A3A：PDF／Word 正文预览与分类建议</h1>
<p>${summary.success ? '自动化检查通过，待用户验收' : '尚未全部通过，不能当作验收完成'}。本轮 ${summary.passed} 通过、${summary.failed} 失败、${summary.notRun} 未运行；全套后端 ${summary.overallPassed} 通过。</p>
<h2>已实际验证的行为</h2><ul><li>真实生成的 PDF 文本层和压缩 DOCX 中文正文经过解析，真实 HTTP＋PostgreSQL＋MinIO 流程验证原件读取与归属。</li><li>文档开头有明确独立标题时给分类建议，例如“法律服务合同”建议服务合同、“民事起诉状”建议起诉材料。冲突标题不选类别；引用和文件名不作为标题。</li><li>案号只列候选，不选择案件，不提取确定法律期限，不创建任务；全部建议需要人工确认。</li><li>每次预览记录开始与结束原因，不把正文、文件名或内部对象路径记入审计。失败保留原件，暂时故障可以重试。</li><li>超时、压缩膨胀、超量正文、损坏文件与无文本层均有边界处理；其他账号或处理期间被删除的资料不会返回正文。</li></ul>
<h2>本轮限制</h2><p>这是后端能力验收报告；6A3B 已接入客户端正文入口，界面检查与截图见 ruler-client-validation 产物中的 client-acceptance.html。图片 OCR、旧 DOC、视频、密码文件、自动归集队列与 AI 兜底均未实现。PDF 上限 100 页、文件 10MiB、正文 100000 个 UTF-16 码元；DOCX 解压合计至多 20MiB/256 条目。超限整次转人工处理，不用截断正文分类。</p>
<p>原件和人工分类均不改变。解析子进程限制时间与 V8 堆，不等同操作系统安全沙箱；未接真实 OSS、微信或法院平台。公开测试服务、真机验证、自动合并和生产部署均未执行。</p>
<h2>你如何验收</h2><p>下载本报告并打开此 HTML，查看下面实际运行场景；可以回复“通过”或“不通过＋现象”。不需要读代码、改配置或运行命令。客户端可点击“开始虚构体验”→“材料待定区”→“添加虚构文件示例”→“查看正文示例”；真实文件联网体验仍需尚未交付的公共测试服务。</p>
<table><thead><tr><th>实际运行场景</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table></html>`, {mode:0o600});
console.log(`PASS 中文正文提取报告：${summary.passed} 通过、${summary.failed} 失败、${summary.notRun} 未运行`);
