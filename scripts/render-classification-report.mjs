import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const path = name => fileURLToPath(new URL(`../test-results/${name}`, import.meta.url));
const backend = JSON.parse(readFileSync(path('auth-validation.json'), 'utf8'));
const database = JSON.parse(readFileSync(path('schema-database.json'), 'utf8'));
function cases(source, name) {
  const suite = source.testResults.find(s => s.name.replaceAll('\\', '/').endsWith(`/${name}`));
  if (!suite || suite.assertionResults.length === 0) throw new Error('缺少分类持久化实际检查，不能生成报告');
  return suite.assertionResults;
}
const tests = [...cases(backend, 'classification.e2e.ts'), ...cases(database, 'classification.integration.ts')];
const passed = tests.filter(t => t.status === 'passed').length, failed = tests.filter(t => t.status === 'failed').length;
const summary = { passed, failed, notRun: tests.length - passed - failed, total: tests.length,
  backendPassed: backend.numPassedTests, databasePassed: database.numPassedTests,
  success: backend.success && database.success && passed === tests.length,
  clientEntry: 'NOT_IMPLEMENTED', automaticPipeline: 'NOT_IMPLEMENTED', realDevice: 'NOT_RUN', cloudCI: 'VERIFY_SEPARATELY' };
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
writeFileSync(path('classification-validation.json'), JSON.stringify(summary, null, 2), { mode: 0o600 });
writeFileSync(path('classification-acceptance.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>RULER 分类结果保存验收</title>
<style>body{font:16px/1.8 system-ui;max-width:1000px;margin:2rem auto;padding:0 1rem;color:#172637}table{border-collapse:collapse;width:100%}td,th{padding:.6rem;border:1px solid #ccd4dc;text-align:left}</style>
<h1>阶段 6A4B1：规则分类结果保存与重登读取</h1>
<p>${summary.success ? '自动化检查通过，待验收' : '检查未全部通过，不能当作验收完成'}：本专项 ${passed} 项通过、${failed} 项失败、${summary.notRun} 项未运行。后端全套 ${summary.backendPassed} 项通过，数据库全套 ${summary.databasePassed} 项通过。云端 CI 状态需另行核验。</p>
<h2>现在完成了什么</h2><p>成功提取时保存分类建议、固定原因和规则版本。真实 DOCX 检查起诉材料、答辩材料、法院文件、传票、服务合同，重新登录或换数据库连接后仍能读到同一次结果。未识别和标题冲突也明确记录；旧版本没有保存过的结果显示“未记录”，不伪造历史。</p>
<p>读取历史不会重新解析、改用新规则或产生归档。分类与成功状态、结束审计一起提交；真实审计写入失败时全部回滚。未知或他人记录拒绝访问；新字段不含正文、案号、文件名或链接。</p>
<h2>你如何验收</h2><p>直接打开这份报告，查看下方虚构场景的实际结果，可回复“通过”或“不通过＋现象”。本轮为后端能力，客户端还没有“查看已保存分类”的入口，无需在旧安装包中寻找按钮，也不需要操作代码。后续任务接通客户端，再继续匹配与处理调度。</p>
<h2>范围和风险</h2><p>全部11类人工选择保留；规则不确定时由用户选择。分类建议始终需要人工确认，不自动归档、不调用AI、不计算法律期限。没有公开测试服务、真机验证、合并或部署。迁移向前增加三个可空字段，保留原件和旧记录；回退保留字段与密钥，旧版本新产生的提取可能没有分类记录。</p>
<table><thead><tr><th>实际检查</th><th>结果</th></tr></thead><tbody>${tests.map(t => `<tr><td>${escape(t.fullName)}</td><td>${t.status === 'passed' ? '通过' : t.status === 'failed' ? '失败' : '未运行'}</td></tr>`).join('')}</tbody></table></html>`, { mode: 0o600 });
console.log(`PASS 中文分类结果报告：${passed} 通过、${failed} 失败、${summary.notRun} 未运行`);
