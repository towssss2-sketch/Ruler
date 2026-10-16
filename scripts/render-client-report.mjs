import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const target = name => fileURLToPath(new URL(`../test-results/${name}`, import.meta.url));
const events = readFileSync(target('client-validation-events.jsonl'), 'utf8').split('\n').filter(line => line.trim().length > 0).map(line => JSON.parse(line));
const names = new Map(events.filter(event => event.type === 'testStart').map(event => [event.test.id, event.test.name]));
const tests = events.filter(event => event.type === 'testDone' && event.hidden === false);
if (!tests.length) throw new Error('缺少真实 Flutter 测试结果');
const passed = tests.filter(test => test.result === 'success' && !test.skipped).length;
const skipped = tests.filter(test => test.skipped).length;
const failed = tests.length - passed - skipped;
const runnerPassed = events.some(event => event.type === 'done' && event.success === true);
const screenshot = readFileSync(target('client-experience-task.png'));
if (!screenshot.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error('缺少实际渲染 PNG');
const summary = { total: tests.length, passed, failed, skipped, success: runnerPassed && failed === 0 && skipped === 0,
  mode: 'FICTIONAL_MEMORY_ONLY', realApi: 'NOT_IMPLEMENTED', fileUpload: 'NOT_IMPLEMENTED',
  persistence: 'NOT_IMPLEMENTED', realDevice: 'NOT_RUN', screenshot: 'FLUTTER_WIDGET_RENDER' };
const escape = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const rows = tests.map(test => `<tr><td>${escape(names.get(test.testID) ?? '未知测试')}</td><td>${test.skipped ? '未运行' : test.result === 'success' ? '通过' : '失败'}</td></tr>`).join('\n');
writeFileSync(target('client-validation.json'), JSON.stringify(summary,null,2));
writeFileSync(target('client-acceptance.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 客户端虚构体验验收</title><style>body{font:16px/1.6 system-ui;max-width:1000px;margin:2rem auto;padding:0 1rem}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border:1px solid #ccd4dc}img{max-width:100%;border:1px solid #ddd}</style>
<h1>阶段11A1：可以点击操作的客户端虚构体验版</h1><p>实际 Flutter 测试：通过 ${passed}，失败 ${failed}，跳过 ${skipped}。${summary.success ? '自动检查通过，待用户验收。' : '未全部通过，不能验收。'}</p>
<h2>安装后这样体验</h2><ol><li>点击“开始虚构体验”，查看空案件列表。</li><li>点击“新建案件”，保留默认虚构信息并创建。</li><li>进入“示例文件”，添加两次示例版本，查看版本标记与示例说明。</li><li>进入“工作任务”，添加任务、标记完成，再恢复待办。</li><li>返回列表搜索案件，进入详情后移除体验案件，确认回到空列表。</li></ol>
<p>所有数据仅在本次运行内存中，退出应用后清除。没有真实登录、云端保存、设备文件读取或文件上传下载；示例 PDF 是列表条目演示，不是真实文档。请勿输入真实案件资料。真实接口接入、缓存及法定期间仍未交付。</p>
<h2>来自实际 Widget 渲染的截图</h2><p>使用系统中文测试字体及实际页面渲染，不是设计稿；不能据此声称真实手机或 Windows 设备安装已验证。</p><img src="client-experience-task.png" alt="真实 Flutter 测试渲染的虚构任务完成页面">
<table><thead><tr><th>真实执行的场景</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table><p>无需阅读代码或运行命令，有空再回复“通过”或“不通过＋现象”。没有自动合并或生产部署。</p></html>`, { mode: 0o600 });
console.log(`PASS 中文客户端报告已生成：${passed} 通过，${failed} 失败，${skipped} 跳过`);
if (!summary.success) process.exitCode = 1;
