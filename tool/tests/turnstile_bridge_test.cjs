const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('lib/widgets/turnstile_dialog.dart','utf8');
function script(name) { return source.match(new RegExp('const '+name+" = r'''([\\s\\S]*?)''';"))[1]; }
function page({official=true,frame=false,origin='https://next.bgm.tv'}={}) {
  const messages=[];const callbacks=[];const listeners=[];
  const render=()=>{};
  const window={addEventListener:(type,fn)=>listeners.push(fn),chrome:{webview:{postMessage:raw=>messages.push(JSON.parse(raw))}},turnstile:{render,getResponse:()=>official?'posting-token':'clearance-token'}};
  window.top=frame?{}:window;
  if(official) window.turnstileCallback=token=>callbacks.push(token);
  let timer;
  const context=vm.createContext({window,location:{origin,pathname:'/p1/turnstile'},document:{getElementById:id=>official&&id==='turnstile-container'?{}:null},setInterval:fn=>{timer=fn;return 1;},clearInterval:()=>{},JSON,String});
  vm.runInContext(script('turnstileBridgeScript'),context);
  if(timer)timer();
  return {messages,callbacks,window,render,listeners,read:()=>vm.runInContext(script('turnstileReadTokenScript'),context)};
}
for(const options of [{official:false},{frame:true},{origin:'https://challenges.cloudflare.com'}]) {
  const p=page(options);assert.deepEqual(p.messages,[]);assert.equal(p.read(),'');assert.equal(p.window.turnstile.render,p.render);
}
const p=page();assert.deepEqual(p.messages,[{token:'posting-token'}]);assert.equal(p.read(),'posting-token');
p.window.turnstileCallback('posting-token');assert.deepEqual(p.callbacks,['posting-token']);assert.equal(p.messages.length,1);assert.equal(p.window.turnstile.render,p.render);
console.log('Posting challenge provenance passed: clearance/iframe tokens excluded; browser and Turnstile APIs intact.');

// Simulate the official page retaining its callback inside render() on load,
// with no getResponse() polling fallback to hide a missed completion event.
let originalCalled=0;
// The isolated page initially has no application container. Use a separate
// minimal load-order context whose DOM marker appears before window.onload.
const messages=[];const events=[];let ready=false;
const window={addEventListener:(type,fn)=>events.push(fn),chrome:{webview:{postMessage:raw=>messages.push(JSON.parse(raw))}},turnstile:{getResponse:()=>''}};
window.top=window;
const context=vm.createContext({window,location:{origin:'https://next.bgm.tv',pathname:'/p1/turnstile'},document:{getElementById:()=>ready?{}:null},setInterval:()=>1,clearInterval:()=>{},JSON,String});
vm.runInContext(script('turnstileBridgeScript'),context);
ready=true;window.turnstileCallback=()=>originalCalled++;
for(const listener of events)listener();
const retainedCallback=window.turnstileCallback;
retainedCallback('official-token-before-navigation');
assert.deepEqual(messages,[{token:'official-token-before-navigation'}]);assert.equal(originalCalled,1);
console.log('Official load-order callback passed: token delivered before retained callback navigates.');
