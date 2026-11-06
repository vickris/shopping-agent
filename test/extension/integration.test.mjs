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

for(const storeName of ['carrefour','quickmart','naivas']) {
test(`${storeName}: installed MV3 extension builds the reviewed basket in the normal store tab`,async()=>{
  const host={carrefour:'www.carrefour.ke',quickmart:'www.quickmart.co.ke',naivas:'www.naivas.online'}[storeName];
  const dir=await mkdtemp(path.join(os.tmpdir(),'shopping-agent-extension-'));
  let context;
  try {
    const extensionDir=path.join(dir,'extension');await cp(new URL('../../extension',import.meta.url),extensionDir,{recursive:true});
    const manifest=JSON.parse(await readFile(path.join(extensionDir,'manifest.json'),'utf8'));
    // Equivalent to a user granting optional retailer access, without a permission dialog in CI.
    manifest.host_permissions=[...manifest.host_permissions,...manifest.optional_host_permissions];
    await writeFile(path.join(extensionDir,'manifest.json'),JSON.stringify(manifest));
    context=await chromium.launchPersistentContext(path.join(dir,'profile'),{channel:'chromium',headless:true,args:[`--disable-extensions-except=${extensionDir}`,`--load-extension=${extensionDir}`,`--host-resolver-rules=MAP ${host} ~NOTFOUND, MAP deal-agent-beta.onrender.com ~NOTFOUND`]});
    await context.route('https://deal-agent-beta.onrender.com/**',route=>route.fulfill({contentType:'text/html',body:'<h1>Shopping Agent checkout export</h1>'}));
    await context.route(`https://${host}/**`,route=>route.fulfill({contentType:'text/html',body:storefront(storeName,{extra:true})}));
    await context.addCookies([{name:'existing-store-session',value:'fixture-login',domain:host,path:'/'}]);
    const app=await context.newPage();await app.goto('https://deal-agent-beta.onrender.com/');
    await app.waitForTimeout(150);
    const plan={version:1,store:storeName,request_id:'demo-request-1234567890',created_at:Math.floor(Date.now()/1000),delivery:storeName==='quickmart'?{branch_id:'73',label:'Nearby branch'}:{label:'Nearby location'},products:[{id:'42',name:'Milk 500ml',query:'milk',url:storeName==='carrefour'?`https://${host}/mafken/en/milk/p/42?offer=retail&sellerId=1&sid=reference`:`https://${host}/milk`,packs:2,expected_price:'62.00'}]};
    const uiEvent=context.waitForEvent('page');
    const accepted=await app.evaluate(plan=>new Promise(resolve=>{
      window.addEventListener('message',event=>{if(event.data?.source==='shopping-agent-extension')resolve(event.data);});
      window.postMessage({source:'shopping-agent',type:'basket:offer',plan},location.origin);
    }),plan);
    assert.equal(accepted.accepted,true);
    assert.equal(accepted.version,manifest.version);
    assert.equal('cookies' in accepted,false);
    const ui=await uiEvent;await ui.waitForURL(/chrome-extension:.*checkout.html/);
    await ui.locator('#open').waitFor();
    await ui.waitForFunction(()=>document.querySelector('#products li')?.textContent.includes('Milk'));
    const storeEvent=context.waitForEvent('page');
    await ui.locator('#open').click();
    const store=await storeEvent;
    // Attach fixture interception before the extension-created tab's next navigation.
    await store.goto(`https://${host}/`,{waitUntil:'load'});
    assert.equal(await store.evaluate(()=>localStorage.getItem('qty')),null);
    assert.equal(await store.evaluate(()=>localStorage.getItem('paid')),null);
    await ui.locator('#resume:not([disabled])').click();
    await ui.waitForFunction(()=>document.querySelector('#status').textContent.includes('Selected products and quantities checked'),{},{timeout:10000});
    assert.equal(await store.evaluate(()=>localStorage.getItem('qty')),'2');
    assert.equal(await store.evaluate(()=>localStorage.getItem('paid')),null);
    assert.equal((await context.cookies(`https://${host}`)).find(c=>c.name==='existing-store-session').value,'fixture-login');
    assert.equal(manifest.permissions.includes('cookies'),false);
    assert.equal(manifest.permissions.includes('debugger'),false);
    assert.equal(manifest.optional_host_permissions.some(host=>host.includes('google')),false);
    await ui.locator('#clear').click();
    await ui.waitForFunction(()=>document.querySelector('#empty').hidden===false);
    assert.equal(store.isClosed(),false);
  } finally {await context?.close();await rm(dir,{recursive:true,force:true});}
});
}
