import {chromium,webkit} from 'playwright';
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {setTimeout as sleep} from 'node:timers/promises';
mkdirSync('artifacts',{recursive:true});
const pageHtml=readFileSync('tests/test.html');
const server=createServer((req,res)=>{res.writeHead(200,{'Content-Type':'text/html'});res.end(pageHtml)});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const url='http://127.0.0.1:'+server.address().port+'/';
const results=[];
const save=o=>{results.push(o);console.log(JSON.stringify(o,null,2))};
async function browserProbe(engine,label,args=[]){
 let b;const r={browser:label,launch:false};
 try{
  b=await engine.launch({headless:true,args,timeout:60000});r.launch=true;
  const page=await b.newPage({viewport:{width:900,height:700}});
  page.on('console',msg=>console.log(label+' '+msg.type()+': '+msg.text().slice(0,300)));
  await page.goto(url,{timeout:30000});
  r.probe=await page.evaluate(()=>Promise.race([window.testGPU(),new Promise((_,reject)=>setTimeout(()=>reject(Error('GPU test timeout')),30000))]));
  await page.screenshot({path:'artifacts/'+label+'.png',fullPage:true});
  r.screenshot='artifacts/'+label+'.png';
 }catch(e){r.error=(e.stack||String(e)).slice(0,2600)}
 finally{try{await b?.close()}catch{}save(r)}
}
await browserProbe(chromium,'chromium',['--enable-unsafe-webgpu']);
await browserProbe(webkit,'playwright-webkit');
async function safariProbe(){
 const r={browser:'native-safari',launch:false};
 let child,session,output='';
 const endpoint='http://127.0.0.1:4444';
 async function api(path,method='GET',body){
  const ctl=new AbortController(),t=setTimeout(()=>ctl.abort(),12000);
  try{const x=await fetch(endpoint+path,{method,body:body===undefined?undefined:JSON.stringify(body),headers:{'Content-Type':'application/json'},signal:ctl.signal});return x.json()}
  finally{clearTimeout(t)}
 }
 try{
  child=spawn('/usr/bin/safaridriver',['-p','4444'],{stdio:['ignore','pipe','pipe']});
  child.stdout.on('data',b=>output+=b.toString());child.stderr.on('data',b=>output+=b.toString());
  await sleep(1500);
  const s=await api('/session','POST',{capabilities:{alwaysMatch:{browserName:'safari'}}});
  session=s.value?.sessionId;if(!session)throw Error('Safari WebDriver session unavailable: '+JSON.stringify(s).slice(0,1100)+' stdout='+output.slice(0,400));
  r.launch=true;
  await api('/session/'+session+'/url','POST',{url});
  const code='var done=arguments[arguments.length-1];window.testGPU().then(done).catch(e=>done({error:String(e)}));';
  const got=await api('/session/'+session+'/execute/async','POST',{script:code,args:[]});r.probe=got.value;
  const png=await api('/session/'+session+'/screenshot');
  if(typeof png.value==='string'){writeFileSync('artifacts/native-safari.png',Buffer.from(png.value,'base64'));r.screenshot='artifacts/native-safari.png'}
 }catch(e){r.error=(e.stack||String(e)).slice(0,2200)}
 finally{
  if(session){try{await api('/session/'+session,'DELETE')}catch{}}
  if(child){child.kill();await sleep(250)}
  r.driverOutput=output.slice(0,900);save(r);
 }
}
await safariProbe();
const rows=['# macOS 26 browser and GPU results','','| Browser | Launch | Screenshot | WebGPU | Adapter | WGSL compute | Triangle |','|---|---|---|---|---|---|---|'];
for(const r of results){const p=r.probe||{};rows.push('| '+r.browser+' | '+!!r.launch+' | '+!!r.screenshot+' | '+!!p.webgpu+' | '+!!p.adapter+' | '+!!p.compute+' | '+!!p.render+' |')}
rows.push('','Playwright WebKit is not Safari.app; native Safari WebDriver is tested separately. WebGPU success may be software-rendered (inspect adapterInfo and Metal inventory).');
for(const r of results)if(r.error||r.probe?.errors?.length)rows.push('','**'+r.browser+'**: `'+String(r.error||r.probe.errors.join('; ')).replaceAll('`',"'").slice(0,700)+'`');
writeFileSync('artifacts/report.md',rows.join('\n')+'\n');writeFileSync('artifacts/results.json',JSON.stringify(results,null,2));
server.close();
