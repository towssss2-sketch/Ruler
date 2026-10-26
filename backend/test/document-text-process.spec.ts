import { ChildProcess } from 'node:child_process';
import processes from 'node:child_process';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { DocumentTextExtractor } from '../src/modules/ingestion/extraction/document-text-extractor';

afterEach((): void => { jest.restoreAllMocks(); jest.useRealTimers(); });
function childFixture(): { child: ChildProcess; kill: jest.Mock; stdin: PassThrough } {
  const child = new EventEmitter(); const kill = jest.fn(); const stdin = new PassThrough();
  Object.assign(child,{kill,stdin});
  jest.spyOn(processes,'fork').mockReturnValue(child as ChildProcess);
  return {child:child as ChildProcess,kill,stdin};
}
describe('解析进程故障与资源隔离', (): void => {
  it('不继承应用凭据/调试参数，返回结果即终止子进程，晚到事件不改结果', async (): Promise<void> => {
    const {child,kill} = childFixture(); const pending = new DocumentTextExtractor().extract(Buffer.from('fake'),'pdf');
    expect(processes.fork).toHaveBeenCalledWith(expect.stringContaining('dist/modules/ingestion/extraction/document-text-worker.js'),
      ['pdf','4'],expect.objectContaining({env:{},execArgv:['--max-old-space-size=128'],stdio:['pipe','ignore','ignore','ipc']}));
    child.emit('message',{state:'TEXT',text:'虚构'}); child.emit('exit',0);
    expect(await pending).toEqual({state:'TEXT',text:'虚构'}); expect(kill).toHaveBeenCalledTimes(1);
  });
  it('超时杀死进程并允许人工重试，不无限等待', async (): Promise<void> => {
    jest.useFakeTimers(); const {kill} = childFixture();
    const pending = new DocumentTextExtractor().extract(Buffer.from('fake'),'pdf');
    await jest.advanceTimersByTimeAsync(15000);
    expect(await pending).toEqual({state:'MANUAL_REQUIRED',reason:'TIMEOUT',retryable:true});
    expect(kill).toHaveBeenCalledWith('SIGKILL'); expect(jest.getTimerCount()).toBe(0);
  });
  it('启动、异常退出及输入管道故障返回固定消息，不暴露子进程内容', async (): Promise<void> => {
    for (const signal of ['error','exit','stdin']) {
      const {child,stdin} = childFixture(); const pending = new DocumentTextExtractor().extract(Buffer.from('fake'),'docx');
      if (signal === 'stdin') stdin.emit('error',new Error('fictional-private-process'));
      else child.emit(signal, signal === 'exit' ? 1 : new Error('fictional-private-process'));
      expect(await pending).toEqual({state:'MANUAL_REQUIRED',reason:'UNAVAILABLE',retryable:true});
      jest.restoreAllMocks();
    }
    jest.spyOn(processes,'fork').mockImplementationOnce((): ChildProcess => { throw new Error('private-spawn-error'); });
    expect(await new DocumentTextExtractor().extract(Buffer.from('fake'),'pdf')).toMatchObject({reason:'UNAVAILABLE'});
  });
});
