import {execFile as rawExec} from 'node:child_process';
import {promisify} from 'node:util';
import {createServer} from 'node:net';
import {realpath} from 'node:fs/promises';
import {dirname,join,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {buildInjection} from './payload.mjs';
import {connect,pageTarget,localSocket} from './cdp.mjs';
const exec=promisify(rawExec);
const root=dirname(dirname(fileURLToPath(import.meta.url)));
async function command(file,args){return (await exec(file,args,{timeout:15000,maxBuffer:1024*1024})).stdout.trim();}
async function freePort(){
  return new Promise((resolve,reject)=>{const server=createServer();server.on('error',reject);server.listen(0,'127.0.0.1',()=>{const port=server.address().port;server.close(error=>error?reject(error):resolve(port));});});
}
export async function verifyListener(port,bundle){
  const records=await command('/usr/sbin/lsof',['-nP',`-iTCP:${port}`,'-sTCP:LISTEN','-Fpn']);
  const pids=[...records.matchAll(/^p(\d+)$/gm)].map(match=>Number(match[1]));
  const addresses=[...records.matchAll(/^n(.+)$/gm)].map(match=>match[1]);
  if(!pids.length||!addresses.length||addresses.some(value=>value!==`127.0.0.1:${port}`))throw new Error('调试端口没有严格限定在 127.0.0.1，停止连接');
  const verified=new Set(),inherited=[];
  for(const pid of new Set(pids)){
    const uid=Number(await command('/bin/ps',['-p',String(pid),'-o','uid=']));
    if(uid!==process.getuid())throw new Error('端口所属用户不匹配');
    const files=await command('/usr/sbin/lsof',['-a','-p',String(pid),'-d','txt','-Fn']);
    const executable=files.split('\n').find(line=>line.startsWith('n'))?.slice(1);
    if(!executable)throw new Error('无法验证调试端口进程');
    if((await realpath(executable)).startsWith(bundle+sep)){verified.add(pid);continue;}
    // Current Codex also passes the listening descriptor to its signed CUA helper.
    const helper=join(process.env.HOME,'.codex/computer-use/Codex Computer Use.app');
    if(await realpath(executable)!==join(helper,'Contents/MacOS/SkyComputerUseService'))throw new Error('调试端口不属于目标 Codex 应用');
    await command('/usr/bin/codesign',['--verify','--deep','--strict',helper]);
    const {stderr:signature}=await exec('/usr/bin/codesign',['-dv','--verbose=4',helper],{timeout:15000});
    if(!signature.includes('TeamIdentifier=2DC432GLL2')||!signature.includes('Identifier=com.openai.sky.CUAService\n'))throw new Error('辅助进程签名不匹配');
    inherited.push(pid);
  }
  if(!verified.size)throw new Error('缺少官方应用监听进程');
  for(const pid of inherited){
    const parent=Number(await command('/bin/ps',['-p',String(pid),'-o','ppid=']));
    if(!verified.has(parent))throw new Error('辅助进程不是官方应用的子进程');
  }
}
async function main(){
  const i=process.argv.indexOf('--bundle');if(i<0||!process.argv[i+1])throw new Error('请从粉色图标的「Codex」应用启动');
  const bundle=await realpath(process.argv[i+1]);
  await command('/usr/bin/codesign',['--verify','--deep','--strict',bundle]);
  const identifier=await command('/usr/libexec/PlistBuddy',['-c','Print :CFBundleIdentifier',join(bundle,'Contents/Info.plist')]);
  if(identifier!=='com.openai.codex')throw new Error('应用标识不匹配');
  const {stderr:signature}=await exec('/usr/bin/codesign',['-dv','--verbose=4',bundle],{timeout:15000});
  if(!signature.includes('TeamIdentifier=2DC432GLL2'))throw new Error('未识别为预期的 OpenAI 签名，停止启动');
  const source=await buildInjection(root),port=await freePort();
  await command('/usr/bin/open',['-n','-a',bundle,'--args','--remote-debugging-address=127.0.0.1',`--remote-debugging-port=${port}`]);
  const deadline=Date.now()+45000;let lastError='等待 Codex 页面';
  while(Date.now()<deadline){
    let client;
    try{
      await verifyListener(port,bundle);
      const response=await fetch(`http://127.0.0.1:${port}/json/list`,{signal:AbortSignal.timeout(1200),redirect:'error'});
      if(!response.ok)throw new Error('调试页面尚未就绪');
      const targets=await response.json();if(!Array.isArray(targets))throw new Error('无效页面列表');
      const target=targets.find(pageTarget);if(!target)throw new Error('尚未找到主窗口');
      client=await connect(localSocket(target.webSocketDebuggerUrl,port));
      const result=await client.call('Runtime.evaluate',{expression:source,returnByValue:true,awaitPromise:true});
      if(result.exceptionDetails||result.result?.value?.installed!==true)throw new Error('外观脚本未能加载');
      for(let attempt=0;attempt<50;attempt++){
        const answer=await client.call('Runtime.evaluate',{expression:'globalThis.__aemeathExtension?.status()',returnByValue:true});
        const state=answer.result?.value;
        if(state?.ready){console.log('已在 Codex 窗口开始播放。辅助进程现在退出；⌘⌥B 打开图片设置。');return;}
        if(state?.phase==='failed'||state?.phase==='timeout')throw new Error('动画素材加载失败，覆盖层已移除');
        await delay(100);
      }
      throw new Error('动画启动确认超时');
    }catch(error){lastError=error.message;}
    finally{client?.close();}
    await delay(150);
  }
  throw new Error('本版本暂未完成接入：'+lastError+'。Codex 安装包未修改；完全退出后从原图标打开即可关闭调试端口。');
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1])main().catch(error=>{console.error(error.message);process.exitCode=1;});
