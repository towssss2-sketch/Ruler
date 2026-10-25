import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
const target = name => new URL(`../test-results/${name}`, import.meta.url);
const data = JSON.parse(readFileSync(target('client-api-validation.json'), 'utf8'));
assert.equal(data.transport, 'REAL_DART_DIO_NEST_POSTGRES_REDIS_MINIO');
assert.equal(data.passed, 20);
assert.equal(data.failed, 0);
assert.equal(data.skipped, 0);
assert.equal(data.scenarios.length, data.passed);
const escape = text => String(text).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
writeFileSync(target('client-api-acceptance.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>RULER 客户端真实联调</title>
<style>body{font:16px/1.8 system-ui;max-width:900px;margin:2rem auto;padding:1rem}li{margin:.6rem 0}</style>
<h1>客户端真实登录、案件、文件与任务联调</h1><p>20 项通过，0 失败，0 跳过。</p>
<p>实际运行应用使用的 Dart/Dio 会话与仓库，连接真实 Nest HTTP、PostgreSQL、Redis、MinIO。
使用随机隔离数据库及虚构账号；测试后清理本次数据。接口调用没有替换成内存演示。</p>
<ol>${data.scenarios.map(name => `<li>通过：${escape(name)}</li>`).join('')}</ol>
<p>本报告验证网络层与数据保存。界面操作另由 Flutter Widget 测试验证；尚未在手机或 Windows 真机连接远程服务。
文件测试读取仓库里的有效虚构 PDF，实际上传后下载并逐字节比较，验证历史版本与新实例重登。本次使用客户端实际快照、流式 MD5 和下载暂存；系统文件选择与保存适配器已实现，但联调未操作 Android/Windows 原生窗口，不代表真机验证通过。
当前下载包未配置公开测试地址，不能直接登录体验。下一步仍需可达测试服务、安全提供虚构账号、系统文件窗口的真机验证。
不要求你运行命令或修改代码；准备好入口后再提供点击验收步骤。</p></html>`);
console.log('PASS 已生成中文真实客户端联调报告');
