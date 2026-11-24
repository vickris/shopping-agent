import test from 'node:test';
import assert from 'node:assert/strict';
import {localHelper} from '../../extension/local_helper.js';
const event=()=>{const listeners=[];return {addListener:fn=>listeners.push(fn),fire:value=>listeners.forEach(fn=>fn(value))};};
const plan=()=>({version:3,request_id:'helper-request-id-123456',created_at:Math.floor(Date.now()/1000),store:'carrefour',products:[{id:'42',name:'Milk',query:'milk',url:'https://www.carrefour.ke/milk/p/42',packs:2,expected_price:'62.00'}]});
test('native helper only accepts app-owned validated baskets, opens on request and never creates tabs',async()=>{
  const sent=[],progress=[],writes=[];
  const port={onMessage:event(),onDisconnect:event(),postMessage:value=>sent.push(value),disconnect(){this.onDisconnect.fire();}};
  const chrome={runtime:{connectNative:()=>port},storage:{session:{set:async value=>writes.push(value)}},tabs:{sendMessage:async(id,value)=>progress.push({id,...value})}};
  const receive=localHelper(chrome),sender={url:'https://deal-agent-beta.onrender.com/',tab:{id:4}};
  await assert.rejects(receive({type:'helper:import',plan:plan()},{url:'https://evil.test/',tab:{id:4}}));
  assert.equal((await receive({type:'helper:import',plan:plan()},sender)).accepted,true);
  assert.deepEqual(sent.map(v=>v.action),['prepare']);
  await assert.rejects(receive({type:'helper:import',plan:plan()},sender));
  const request_id=sent[0].plan.request_id;
  port.onMessage.fire({request_id,status:'ready',message:'Verified'});
  await assert.rejects(receive({type:'helper:control',request_id,action:'focus'},{...sender,tab:{id:5}}));
  await receive({type:'helper:control',request_id,action:'focus'},sender);
  assert.deepEqual(sent.map(v=>v.action),['prepare','open']);
  await receive({type:'helper:control',request_id,action:'stop'},sender);
  assert.equal(sent.at(-1).action,'close');
  assert.ok(progress.some(value=>value.status==='ready'));
});

test('the app hook routes local offers and checkout controls to the helper and requires version 0.5',async()=>{
  const {readFile}=await import('node:fs/promises');
  const source=await readFile(new URL('../../assets/js/browser_checkout.js',import.meta.url),'utf8');
  const {BrowserCheckout}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  const previousWindow=globalThis.window,previousLocation=globalThis.location;
  const sent=[],status={textContent:''};
  const actions=['focus','resume','stop'].map(action=>({dataset:{checkoutAction:action},hidden:true}));
  let offer,listener;
  globalThis.location={origin:'https://deal-agent-beta.onrender.com'};
  globalThis.window={postMessage:value=>sent.push(value),addEventListener:(_type,fn)=>{listener=fn;},removeEventListener(){}};
  const hook={el:{dataset:{store:'carrefour',transport:'local-helper'},querySelector:()=>status,querySelectorAll:()=>actions,addEventListener(){},removeEventListener(){}},handleEvent:(_event,fn)=>{offer=fn;}};
  try {
    BrowserCheckout.mounted.call(hook);
    offer({plan:plan()});
    assert.equal(sent[0].type,'helper:offer');
    const progress=version=>({source:window,origin:location.origin,data:{source:'shopping-agent-extension',type:'basket:progress',request_id:plan().request_id,version,status:'ready',message:'Verified'}});
    listener(progress('0.4.0'));
    assert.match(status.textContent,/0.5.0 or newer/);
    listener(progress('0.5.0'));
    assert.equal(actions[0].hidden,false);
    assert.equal(actions[1].hidden,true);
    assert.equal(actions[2].hidden,false);
    hook.sendControl('focus');
    assert.equal(sent.at(-1).type,'helper:control');
  } finally {BrowserCheckout.destroyed.call(hook);globalThis.window=previousWindow;globalThis.location=previousLocation;}
});
