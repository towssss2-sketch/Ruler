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
const onlineScreenshot = readFileSync(target('client-online-task.png'));
if (!onlineScreenshot.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error('缺少连接版实际渲染 PNG');
const fileScreenshot = readFileSync(target('client-files.png'));
if (!fileScreenshot.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error('缺少文件页面实际渲染 PNG');
const uploadScreenshot = readFileSync(target('client-upload.png'));
if (!uploadScreenshot.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error('缺少上传界面实际渲染 PNG');
const summary = { total: tests.length, passed, failed, skipped, success: runnerPassed && failed === 0 && skipped === 0,
  mode: 'OFFLINE_DEMO_AND_API_UI', realApi: 'SEPARATE_CLIENT_API_REPORT', fileUpload: 'SYSTEM_ADAPTERS_IMPLEMENTED_REAL_DEVICE_NOT_RUN',
  persistence: 'SERVER_ONLY_NO_LOCAL_CACHE', publicTestService: 'NOT_AVAILABLE',
  realDevice: 'NOT_RUN', screenshot: 'FLUTTER_WIDGET_RENDER_PROTOCOL_FIXTURE' };
const escape = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const rows = tests.map(test => `<tr><td>${escape(names.get(test.testID) ?? '未知测试')}</td><td>${test.skipped ? '未运行' : test.result === 'success' ? '通过' : '失败'}</td></tr>`).join('\n');
writeFileSync(target('client-validation.json'), JSON.stringify(summary,null,2));
writeFileSync(target('client-acceptance.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 客户端界面与会话检查</title><style>body{font:16px/1.6 system-ui;max-width:1000px;margin:2rem auto;padding:0 1rem}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border:1px solid #ccd4dc}img{max-width:100%;border:1px solid #ddd}</style>
<h1>阶段11A2B2：设备文件选择、上传与保存检查</h1><p>实际 Flutter 测试：通过 ${passed}，失败 ${failed}，跳过 ${skipped}。${summary.success ? '自动检查通过；尚缺可达测试服务，不代表真机体验已完成。' : '未全部通过，不能验收。'}</p>
<p>测试服务登录、案件、常规任务和案件文件列表页面已实现。下表界面测试使用协议替身；实际 Dart/Dio 到 Nest、PostgreSQL、Redis、MinIO 的 9 项联调请查看 ruler-client-api-validation 产物。当前安装包没有预置服务地址和账号，登录入口明确提示尚未开放。</p>
<h2>连接版实际界面渲染</h2><p>截图来自 Widget 测试，数据为虚构协议替身；真实后端联调独立验证，尚非真机截图。</p><img src="client-online-task.png" alt="连接版工作任务完成页面的实际 Widget 渲染">
<h2>案件文件页面实际渲染</h2><p>分类、历史版本、分页和删除已经接入真实接口；截图使用虚构协议数据。已接入系统选择与本机保存适配器；操作系统窗口尚待真机验收。</p><img src="client-files.png" alt="案件文件分类与历史版本的实际 Widget 渲染">
<h2>上传失败恢复的实际页面</h2><p>界面协议替身模拟登记失败，保留原文件和票据供重试，不代表真实系统选择器截图。</p><img src="client-upload.png" alt="文件选择后登记失败与重试入口的实际 Widget 渲染">
<h2>安装后这样体验</h2><ol><li>点击“开始虚构体验”，查看空案件列表。</li><li>点击“新建案件”，保留默认虚构信息并创建。</li><li>进入“示例文件”，添加两次示例版本，查看版本标记与示例说明。</li><li>进入“工作任务”，添加任务、标记完成，再恢复待办。</li><li>返回列表搜索案件，进入详情后移除体验案件，确认回到空列表。</li></ol>
<p>以上步骤仅为保留的离线体验，数据退出后清除，示例 PDF 不是实际文档。连接版已实现真实登录、服务端保存和文件传输核心，但公开测试服务、账号交付、设备真机验证、离线缓存和法定期间仍未交付。请勿输入真实资料。</p>
<h2>来自实际 Widget 渲染的截图</h2><p>使用系统中文测试字体及实际页面渲染，不是设计稿；不能据此声称真实手机或 Windows 设备安装已验证。</p><img src="client-experience-task.png" alt="真实 Flutter 测试渲染的虚构任务完成页面">
<table><thead><tr><th>真实执行的场景</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table><p>无需阅读代码或运行命令，有空再回复“通过”或“不通过＋现象”。没有自动合并或生产部署。</p></html>`, { mode: 0o600 });
console.log(`PASS 中文客户端报告已生成：${passed} 通过，${failed} 失败，${skipped} 跳过`);
if (!summary.success) process.exitCode = 1;
