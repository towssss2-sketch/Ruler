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
for (const name of ['client-categories.png', 'client-category-demo.png', 'client-case-edit.png', 'client-case-edit-demo.png', 'client-parties-editor.png', 'client-parties-detail.png', 'client-parties-demo.png', 'client-create-parties.png', 'client-conflicts.png', 'client-case-filters.png', 'client-case-filters-demo.png', 'client-case-supplement-editor.png', 'client-case-supplement-demo.png', 'client-task-edit.png', 'client-task-edit-demo.png', 'client-today.png', 'client-today-demo.png']) {
  if (!readFileSync(target(name)).subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error('缺少分类界面实际渲染 PNG');
}
const summary = { total: tests.length, passed, failed, skipped, success: runnerPassed && failed === 0 && skipped === 0,
  mode: 'OFFLINE_DEMO_AND_API_UI', realApi: 'SEPARATE_CLIENT_API_REPORT', fileUpload: 'SYSTEM_ADAPTERS_IMPLEMENTED_REAL_DEVICE_NOT_RUN',
  persistence: 'SERVER_ONLY_NO_LOCAL_CACHE', publicTestService: 'NOT_AVAILABLE',
  realDevice: 'NOT_RUN', screenshot: 'FLUTTER_WIDGET_RENDER_PROTOCOL_FIXTURE' };
const escape = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const rows = tests.map(test => `<tr><td>${escape(names.get(test.testID) ?? '未知测试')}</td><td>${test.skipped ? '未运行' : test.result === 'success' ? '通过' : '失败'}</td></tr>`).join('\n');
writeFileSync(target('client-validation.json'), JSON.stringify(summary,null,2));
writeFileSync(target('client-acceptance.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RULER 客户端界面与会话检查</title><style>body{font:16px/1.6 system-ui;max-width:1000px;margin:2rem auto;padding:0 1rem}table{border-collapse:collapse;width:100%}td,th{padding:.5rem;border:1px solid #ccd4dc}img{max-width:100%;border:1px solid #ddd}</style>
<h1>案件编辑、文件分类与客户端体验检查</h1><p>实际 Flutter 测试：通过 ${passed}，失败 ${failed}，跳过 ${skipped}。${summary.success ? '自动检查通过；尚缺可达测试服务，不代表真机体验已完成。' : '未全部通过，不能验收。'}</p>
<p>测试服务登录、案件、常规任务和案件文件列表页面已实现。下表界面测试使用协议替身；实际 Dart/Dio 到 Nest、PostgreSQL、Redis、MinIO 的 16 项联调请查看 ruler-client-api-validation 产物。当前安装包没有预置服务地址和账号，登录入口明确提示尚未开放。</p>
<h2>今日任务汇总</h2><p>案件列表右上角“今日任务”入口汇总本人全部案件的未完成任务，按已确认期间、逾期、今日到期显示。标注案号与法院，可打开所属案件；完成后回第一页重读。迷你日历仅标记汇总日期，不是完整日程；在线按服务端北京时间，离线只读本次内存。法定期间图为虚构协议夹具，不代表期间计算、登记或提醒已实现。</p><img src="client-today.png" alt="在线今日任务协议测试截图"><img src="client-today-demo.png" alt="窄屏深色离线今日任务实际渲染"><h2>常规任务编辑</h2><p>可修改任务标题、描述和工作日期；留空保存清除描述/日期，保留完成状态。在线新建也可填写描述，离线先添加任务再编辑。日期不代表法定期间，不执行计算或提醒。在线图使用协议替身，离线图为当前内存体验。</p><img src="client-task-edit.png" alt="任务编辑表单"><img src="client-task-edit-demo.png" alt="窄屏深色任务编辑结果"><h2>其他案件资料编辑</h2><p>在案件详情中编辑审判员、书记员、电话、费用、费用状态和备注。金额保留两位小数，留空保存会清除原值；费用状态只作记录，不执行收付款。失败保留草稿，保存后独立重读。在线图使用协议替身，离线图来自当前内存体验。</p><img src="client-case-supplement-editor.png" alt="其他案件资料编辑"><img src="client-case-supplement-demo.png" alt="窄屏离线资料保存后详情"><h2>案件筛选与排序</h2><p>关键词与法院全称、阶段、状态一起生效，支持更新时间正反排序；切换条件回到第一页，取消不查询、清除筛选保留关键词。离线为当前内存记录，在线截图使用协议替身，真实数据库另有联调。</p><img src="client-case-filters.png" alt="案件筛选表单"><img src="client-case-filters-demo.png" alt="窄屏深色离线筛选结果"><h2>新建多人名单与利益冲突检查</h2><p>新建时可编辑完整名单，一次保存。离线图来自可点击的虚构体验；冲突结果图使用协议替身，真实 PostgreSQL 匹配另经联调验证。检查只提示姓名相似，需人工核对；离线不执行匹配。</p><img src="client-create-parties.png" alt="离线多人建案"><img src="client-conflicts.png" alt="利益冲突候选与分页"><h2>当事人与案件详情</h2><p>支持查看授权详情、添加/修改/移除原告、被告、第三人，并填写或清空可选资料。在线图使用虚构协议替身，离线图来自实际内存体验，均为 Widget 渲染；没有公网服务或真机验证。</p><img src="client-parties-editor.png" alt="当事人编辑"><img src="client-parties-detail.png" alt="保存后案件详情"><img src="client-parties-demo.png" alt="窄屏虚构当事人体验"><h2>案件编辑实际界面</h2><p>可修改案号、案由、法院、审理阶段和案件状态；失败保留输入，结案保留文件和待办任务。在线截图使用协议替身，离线截图来自内存虚构体验；不代表真机或公网服务。</p><img src="client-case-edit.png" alt="案件编辑表单"><img src="client-case-edit-demo.png" alt="窄屏离线编辑结果"><h2>分类归档实际界面</h2><p>保留原九类，新增法院文件和服务合同；上传必须选分类，列表按当前页类别分组。自动识别分类未接入。以下截图为实际 Widget 渲染，在线页使用协议替身。</p><img src="client-categories.png" alt="文件分类分组"><img src="client-category-demo.png" alt="无需登录的分类演示"><h2>连接版实际界面渲染</h2><p>截图来自 Widget 测试，数据为虚构协议替身；真实后端联调独立验证，尚非真机截图。</p><img src="client-online-task.png" alt="连接版工作任务完成页面的实际 Widget 渲染">
<h2>案件文件页面实际渲染</h2><p>分类、历史版本、分页和删除已经接入真实接口；截图使用虚构协议数据。已接入系统选择与本机保存适配器；操作系统窗口尚待真机验收。</p><img src="client-files.png" alt="案件文件分类与历史版本的实际 Widget 渲染">
<h2>上传失败恢复的实际页面</h2><p>界面协议替身模拟登记失败，保留原文件和票据供重试，不代表真实系统选择器截图。</p><img src="client-upload.png" alt="文件选择后登记失败与重试入口的实际 Widget 渲染">
<h2>安装后这样体验</h2><ol><li>点击“开始虚构体验”，查看空案件列表。</li><li>点击“新建案件”，点击“编辑新建名单”，添加虚构被告，点击“完成名单”再创建。</li><li>在“案件信息”点击“编辑案件信息”，修改案由、选择二审及已结案，保存后可再改回进行中。</li><li>打开“案件详情与当事人”→“编辑当事人”，填写虚构姓名、添加被告并保存；再次编辑可修改或移除。</li><li>进入“示例文件”，添加两次示例版本，查看版本标记与示例说明。</li><li>进入“工作任务”，添加任务、标记完成，再恢复待办。</li><li>返回列表搜索案件，进入详情后移除体验案件，确认回到空列表。</li></ol>
<p>以上步骤仅为保留的离线体验，数据退出后清除，示例 PDF 不是实际文档。连接版已实现真实登录、服务端保存和文件传输核心，但公开测试服务、账号交付、设备真机验证、离线缓存和法定期间仍未交付。请勿输入真实资料。</p>
<h2>来自实际 Widget 渲染的截图</h2><p>使用系统中文测试字体及实际页面渲染，不是设计稿；不能据此声称真实手机或 Windows 设备安装已验证。</p><img src="client-experience-task.png" alt="真实 Flutter 测试渲染的虚构任务完成页面">
<table><thead><tr><th>真实执行的场景</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table><p>无需阅读代码或运行命令，有空再回复“通过”或“不通过＋现象”。没有自动合并或生产部署。</p></html>`, { mode: 0o600 });
console.log(`PASS 中文客户端报告已生成：${passed} 通过，${failed} 失败，${skipped} 跳过`);
if (!summary.success) process.exitCode = 1;
