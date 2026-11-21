import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,cp,readFile,writeFile,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../priv/carrefour_browser/package.json',import.meta.url));
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium}=require('playwright');
const {storefront}=await import('./fixtures.mjs');
const hookSource=await readFile(new URL('../../assets/js/browser_checkout.js',import.meta.url),'utf8');
const appHTML=store=>`<h1>Shopping Agent</h1><section id="checkout" data-store="${store}"><p data-browser-checkout-status role="status"></p><button data-checkout-action="setup" hidden>Enable access</button><button data-checkout-action="focus" hidden>Open store</button><button data-checkout-action="resume" hidden>Resume</button><button data-checkout-action="stop" hidden>Stop</button></section><script type="module">import {BrowserCheckout} from '/checkout-hook.js';const hook={el:document.querySelector('#checkout'),handleEvent:(_event,fn)=>{window.offer=plan=>fn({plan});}};BrowserCheckout.mounted.call(hook);window.progress=[];window.addEventListener('message',event=>{if(event.data?.type==='basket:progress')window.progress.push(event.data);});</script>`;
const send=async(app,plan)=>app.evaluate(plan=>new Promise(resolve=>{
  const listener=event=>{if(event.data?.source==='shopping-agent-extension' && event.data.request_id===plan.request_id && !event.data.type){window.removeEventListener('message',listener);resolve(event.data);}};
  window.addEventListener('message',listener);window.offer(plan);
}),plan);
const control=async(app,request_id,action)=>app.evaluate(({request_id,action})=>new Promise(resolve=>{
  const listener=event=>{if(event.data?.source==='shopping-agent-extension' && event.data.request_id===request_id && event.data.control){window.removeEventListener('message',listener);resolve(event.data);}};
  window.addEventListener('message',listener);window.postMessage({source:'shopping-agent',type:'basket:control',request_id,action},location.origin);
}),{request_id,action});

for(const storeName of ['carrefour','quickmart','naivas']) {
test(`${storeName}: prepares two fresh carts in the background and notifies the shopping page`,async()=>{
  const host={carrefour:'www.carrefour.ke',quickmart:'www.quickmart.co.ke',naivas:'www.naivas.online'}[storeName];
  const dir=await mkdtemp(path.join(os.tmpdir(),'shopping-agent-extension-'));
  let context;
  try {
    const extensionDir=path.join(dir,'extension');await cp(new URL('../../extension',import.meta.url),extensionDir,{recursive:true});
    const manifest=JSON.parse(await readFile(path.join(extensionDir,'manifest.json'),'utf8'));
    manifest.host_permissions=[...manifest.host_permissions,...manifest.optional_host_permissions];
    await writeFile(path.join(extensionDir,'manifest.json'),JSON.stringify(manifest));
    context=await chromium.launchPersistentContext(path.join(dir,'profile'),{channel:'chromium',headless:true,args:[`--disable-extensions-except=${extensionDir}`,`--load-extension=${extensionDir}`,`--host-resolver-rules=MAP ${host} ~NOTFOUND, MAP deal-agent-beta.onrender.com ~NOTFOUND`]});
    await context.route('https://deal-agent-beta.onrender.com/**',route=>route.fulfill({contentType:'text/html',body:appHTML(storeName)}));
    await context.route('https://deal-agent-beta.onrender.com/checkout-hook.js',route=>route.fulfill({contentType:'application/javascript',body:hookSource}));
    await context.route(`https://${host}/**`,route=>route.fulfill({contentType:'text/html',body:storefront(storeName,{extra:true})}));
    await context.addInitScript(({host})=>{if(location.hostname===host && !localStorage.getItem('seeded')){localStorage.setItem('qty','3');localStorage.setItem('extra','1');localStorage.setItem('seeded','true');}},{host});
    await context.addCookies([{name:'existing-store-session',value:'fixture-login',domain:host,path:'/'}]);
    const app=await context.newPage();await app.goto('https://deal-agent-beta.onrender.com/');await app.bringToFront();
    await app.waitForFunction(()=>window.offer && window.progress);await app.waitForTimeout(150);
    const plan={version:3,store:storeName,request_id:'demo-request-1234567890',created_at:Math.floor(Date.now()/1000),delivery:storeName==='quickmart'?{branch_id:'73',label:'Nearby branch'}:{label:'Nearby location'},products:[{id:'42',name:'Milk 500ml',query:'milk',url:storeName==='carrefour'?`https://${host}/mafken/en/milk/p/42?offer=retail&sellerId=1&sid=reference`:`https://${host}/milk`,packs:2,expected_price:'62.00'}]};
    if(storeName==='carrefour') {
      const invalid=structuredClone(plan);invalid.products[0].url+='&token=private';
      const rejected=await send(app,invalid);
      assert.match(rejected.error,/42: unsupported URL parameters/);
      assert.ok(rejected.error.includes(`checkout ${manifest.version}; offer-links-v2`));
    }
    const storeEvent=context.waitForEvent('page');const accepted=await send(app,plan);
    assert.equal(accepted.accepted,true);assert.equal(accepted.background,true);assert.equal(accepted.version,manifest.version);
    const store=await storeEvent;
    await app.locator('#browser-cart-notification').waitFor({state:'visible',timeout:45000});
    assert.equal(context.pages().some(page=>page.url().startsWith('chrome-extension:')),false);
    assert.equal(await store.evaluate(()=>localStorage.getItem('qty')),'2');
    assert.equal(await store.evaluate(()=>localStorage.getItem('extra')),'0');
    assert.equal(await store.evaluate(()=>localStorage.getItem('paid')),null);
    assert.equal((await context.cookies(`https://${host}`)).find(c=>c.name==='existing-store-session').value,'fixture-login');
    const worker=context.serviceWorkers()[0];
    const active=await worker.evaluate(()=>chrome.tabs.query({active:true,currentWindow:true}));
    assert.equal(active[0].url,'https://deal-agent-beta.onrender.com/');
    assert.match(await app.locator('[data-browser-checkout-status]').innerText(),/Fresh cart verified/);
    assert.ok((await app.evaluate(()=>window.progress)).some(event=>event.message.includes('Clearing the previous supermarket cart')));
    // An old request and another app tab cannot control this transfer.
    assert.match((await control(app,'stale-request-123456789','stop')).error,/replaced/);
    const other=await context.newPage();await other.goto('https://deal-agent-beta.onrender.com/');await other.waitForFunction(()=>window.offer);await other.waitForTimeout(150);
    assert.match((await control(other,plan.request_id,'stop')).error,/source is not allowed/);await other.close();await app.bringToFront();
    // Resuming an interrupted verification does not clear or add the order again.
    await worker.evaluate(async()=>{const {job}=await chrome.storage.session.get('job');await chrome.storage.session.set({job:{...job,status:'attention',message:'Simulated verification interruption'}});});
    await app.locator('[data-checkout-action="resume"]').waitFor({state:'visible'});
    const clearsBefore=(await app.evaluate(()=>window.progress)).filter(event=>event.message.includes('Clearing the previous supermarket cart')).length;
    await app.locator('[data-checkout-action="resume"]').click();
    await app.waitForFunction(()=>document.querySelector('#checkout').dataset.checkoutState==='ready',{},{timeout:20000});
    assert.equal(await store.evaluate(()=>localStorage.getItem('qty')),'2');
    assert.equal((await app.evaluate(()=>window.progress)).filter(event=>event.message.includes('Clearing the previous supermarket cart')).length,clearsBefore);
    // A new order supersedes an interrupted transfer without a Stop detour.
    await worker.evaluate(async()=>{const {job}=await chrome.storage.session.get('job');await chrome.storage.session.set({job:{...job,status:'attention',message:'Simulated interrupted order'}});});
    const nextPlan={...plan,request_id:'second-request-1234567890',products:plan.products.map(p=>({...p,packs:1}))};
    // Never reuse a helper that the shopper has moved to checkout/payment.
    const checkingOut=storeName==='carrefour';
    if(checkingOut)await store.goto(`https://${host}/mafken/en/checkout`);
    const pageCount=context.pages().length;
    const nextStoreEvent=checkingOut?context.waitForEvent('page'):null;
    assert.equal((await send(app,nextPlan)).accepted,true);
    const nextStore=checkingOut?await nextStoreEvent:store;
    assert.equal(context.pages().length,pageCount+(checkingOut?1:0));
    if(checkingOut)assert.equal(store.url(),`https://${host}/mafken/en/checkout`);
    await app.locator('#browser-cart-notification').waitFor({state:'visible',timeout:45000});
    assert.equal(await nextStore.evaluate(()=>localStorage.getItem('qty')),'1');
    assert.equal(await nextStore.evaluate(()=>localStorage.getItem('extra')),'0');
    assert.equal(await nextStore.evaluate(()=>localStorage.getItem('paid')),null);
    assert.equal(manifest.permissions.includes('cookies'),false);assert.equal(manifest.permissions.includes('debugger'),false);
    await app.locator('#browser-cart-notification button').filter({hasText:'Open cart'}).click();
    await app.waitForTimeout(100);
    assert.equal((await worker.evaluate(()=>chrome.tabs.query({active:true,currentWindow:true})))[0].url,nextStore.url());
    assert.equal((await control(app,nextPlan.request_id,'stop')).ok,true);
    assert.equal(nextStore.isClosed(),false); // Ready cart is left for the shopper.
  } finally {await context?.close();await rm(dir,{recursive:true,force:true});}
});
}


test('first-time store access is requested only after an explicit setup click',async()=>{
  const dir=await mkdtemp(path.join(os.tmpdir(),'shopping-agent-permissions-'));let context;
  try {
    const extensionDir=path.join(dir,'extension');await cp(new URL('../../extension',import.meta.url),extensionDir,{recursive:true});
    context=await chromium.launchPersistentContext(path.join(dir,'profile'),{channel:'chromium',headless:true,args:[`--disable-extensions-except=${extensionDir}`,`--load-extension=${extensionDir}`,'--host-resolver-rules=MAP deal-agent-beta.onrender.com ~NOTFOUND']});
    await context.route('https://deal-agent-beta.onrender.com/**',route=>route.fulfill({contentType:'text/html',body:appHTML('carrefour')}));
    await context.route('https://deal-agent-beta.onrender.com/checkout-hook.js',route=>route.fulfill({contentType:'application/javascript',body:hookSource}));
    const app=await context.newPage();await app.goto('https://deal-agent-beta.onrender.com/');await app.waitForFunction(()=>window.offer);await app.waitForTimeout(150);
    const plan={version:3,store:'carrefour',request_id:'permission-request-123456',created_at:Math.floor(Date.now()/1000),products:[{id:'42',name:'Milk',query:'milk',url:'https://www.carrefour.ke/mafken/en/milk/p/42',packs:1,expected_price:'62.00'}]};
    assert.equal((await send(app,plan)).status,'permission_required');
    await app.locator('[data-checkout-action="setup"]').waitFor({state:'visible'});
    assert.equal(context.pages().some(page=>page.url().startsWith('chrome-extension:')),false);
    assert.equal(context.pages().some(page=>page.url().includes('carrefour.ke')),false);
    const setupEvent=context.waitForEvent('page');await app.locator('[data-checkout-action="setup"]').click();
    const setup=await setupEvent;await setup.waitForURL(/chrome-extension:.*checkout.html/);
    await setup.locator('#open:not([disabled])').waitFor();
    assert.equal(await setup.locator('#open').innerText(),'Enable background checkout');
  } finally {await context?.close();await rm(dir,{recursive:true,force:true});}
});

test('Del Monte and toothpaste: clears every old line before adding both SKUs and notifies once',async()=>{
  const dir=await mkdtemp(path.join(os.tmpdir(),'shopping-agent-two-products-'));let context;
  try {
    const {carrefourOrderFixture}=await import('./fixtures.mjs');
    const extensionDir=path.join(dir,'extension');await cp(new URL('../../extension',import.meta.url),extensionDir,{recursive:true});
    const manifest=JSON.parse(await readFile(path.join(extensionDir,'manifest.json'),'utf8'));
    manifest.host_permissions=[...manifest.host_permissions,...manifest.optional_host_permissions];
    await writeFile(path.join(extensionDir,'manifest.json'),JSON.stringify(manifest));
    context=await chromium.launchPersistentContext(path.join(dir,'profile'),{channel:'chromium',headless:true,args:[`--disable-extensions-except=${extensionDir}`,`--load-extension=${extensionDir}`,'--host-resolver-rules=MAP www.carrefour.ke ~NOTFOUND, MAP deal-agent-beta.onrender.com ~NOTFOUND']});
    await context.route('https://deal-agent-beta.onrender.com/**',route=>route.fulfill({contentType:'text/html',body:appHTML('carrefour')}));
    await context.route('https://deal-agent-beta.onrender.com/checkout-hook.js',route=>route.fulfill({contentType:'application/javascript',body:hookSource}));
    await context.route('https://www.carrefour.ke/**',route=>route.fulfill({contentType:'text/html',body:carrefourOrderFixture(new URL(route.request().url()).pathname.match(/\/p\/(\d+)$/)?.[1])}));
    const app=await context.newPage();await app.goto('https://deal-agent-beta.onrender.com/');await app.bringToFront();await app.waitForFunction(()=>window.offer);await app.waitForTimeout(150);
    const plan={version:3,store:'carrefour',request_id:'two-product-request-123456',created_at:Math.floor(Date.now()/1000),products:[
      {id:'38605',name:'Del Monte Tropical Blend Juice 1L',query:'delmonte',url:'https://www.carrefour.ke/mafken/en/juice/p/38605?offer=offer_carrefour_&sid=SLOTTED&sellerId=0000',packs:1,expected_price:'265.00'},
      {id:'120137',name:'Pepsodent Herbal Toothpaste Twin Pack 2x150g',query:'toothpaste',url:'https://www.carrefour.ke/mafken/en/herbal-toothpaste/p/120137?offer=offer_carrefour_&sid=SLOTTED&sellerId=0000',packs:3,expected_price:'374.00'}
    ]};
    const storeEvent=context.waitForEvent('page');assert.equal((await send(app,plan)).accepted,true);const store=await storeEvent;
    await app.locator('#browser-cart-notification').waitFor({state:'visible',timeout:45000});
    assert.deepEqual(await store.evaluate(()=>JSON.parse(localStorage.getItem('basket'))),{'99':0,'38605':1,'120137':3});
    const changes=await store.evaluate(()=>JSON.parse(localStorage.getItem('changes')));
    const firstAddition=changes.find(change=>change.quantity>(change.before[change.id]||0));
    assert.ok(firstAddition);assert.equal(Object.values(firstAddition.before).every(q=>q===0),true);
    const progress=await app.evaluate(()=>window.progress);
    assert.equal(progress.filter(event=>event.status==='ready').length,1);
    const additions=progress.filter(event=>event.message.startsWith('Adding product'));
    assert.ok(additions.some(event=>event.message.includes('1 of 2: Del Monte')));
    assert.ok(additions.some(event=>event.message.includes('2 of 2: Pepsodent')));
    const clearIndex=progress.findIndex(event=>event.message.startsWith('Clearing the previous'));
    assert.ok(clearIndex>=0);assert.equal(progress.slice(clearIndex).some(event=>event.message.startsWith('Connecting')),false);
    const worker=context.serviceWorkers()[0];
    assert.equal((await worker.evaluate(()=>chrome.tabs.query({active:true,currentWindow:true})))[0].url,'https://deal-agent-beta.onrender.com/');
    assert.equal(context.pages().some(page=>page.url().startsWith('chrome-extension:')),false);
  } finally {await context?.close();await rm(dir,{recursive:true,force:true});}
});
