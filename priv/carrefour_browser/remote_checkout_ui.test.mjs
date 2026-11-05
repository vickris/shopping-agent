import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium}=await import('playwright');
const {remoteCheckout}=await import('./remote_checkout.mjs');

test('phone-sized viewer scales clicks and sends text, keys and payment-tab selection',async()=>{
  const browser=await chromium.launch({headless:true,channel:'chromium'});
  let hookMounted=false, viewer;
  try {
    const context=await browser.newContext({viewport:{width:1024,height:768}});
    await context.route('https://checkout.test/**',route=>route.fulfill({contentType:'text/html',body:`<input id="address" style="position:absolute;top:10px;left:10px;width:400px;height:50px"><button onclick="window.open('/payment')" style="position:absolute;top:80px;left:10px">Payment</button>`}));
    const store=await context.newPage();await store.goto('https://checkout.test/cart');
    const remote=remoteCheckout(()=>store);
    viewer=await browser.newPage({viewport:{width:390,height:844}});
    await viewer.setContent(`<div id="viewer"><div data-remote-status></div><select data-remote-tabs></select><div data-remote-dialog hidden><button data-remote-dialog="accept">OK</button></div><button data-remote-key="Tab">Next</button><button data-remote-key="Enter">Enter</button><button data-remote-scroll="600">Down</button><img data-remote-screen style="width:100%;height:auto"><input type="password" data-remote-input></div>`);
    const hookSource=(await readFile(new URL('../../assets/js/remote_checkout.js',import.meta.url),'utf8')).replace('export const RemoteCheckout','window.RemoteCheckout');
    await viewer.addScriptTag({content:hookSource});
    await viewer.exposeFunction('control',async payload=>({remote_frame:await remote(payload.remote_input)}));
    await viewer.evaluate(()=>{
      window.hook={...window.RemoteCheckout,el:document.getElementById('viewer'),pushEvent:(_,payload,reply)=>window.control(payload).then(reply)};
      window.hook.mounted();
    });
    hookMounted=true;
    await viewer.waitForFunction(()=>document.querySelector('[data-remote-screen]').naturalWidth===1024);
    const screen=viewer.locator('[data-remote-screen]');
    const rect=await screen.boundingBox();
    await screen.click({position:{x:rect.width*30/1024,y:rect.height*30/768}});
    await viewer.locator('[data-remote-input]').fill('Nairobi');
    await store.waitForFunction(()=>document.getElementById('address').value==='Nairobi');
    assert.equal(await viewer.locator('[data-remote-input]').inputValue(),'');
    await viewer.locator('[data-remote-input]').press('Backspace');
    await store.waitForFunction(()=>document.getElementById('address').value==='Nairob');
    await screen.click({position:{x:rect.width*30/1024,y:rect.height*90/768}});
    await viewer.waitForFunction(()=>document.querySelector('[data-remote-tabs]').options.length===2);
    await viewer.locator('select').selectOption('1');
    await viewer.waitForFunction(()=>window.hook.status.textContent.includes('Connected')&&!window.hook.running&&window.hook.tabs.value==='1');
    assert.equal(context.pages().length,2);
    await viewer.evaluate(()=>window.hook.disconnected());
    assert.equal(await viewer.locator('img').getAttribute('src'),null);
    assert.match(await viewer.locator('[data-remote-status]').innerText(),/Connection interrupted/);
    await viewer.evaluate(()=>window.hook.destroyed());hookMounted=false;
    assert.equal(await viewer.locator('img').getAttribute('src'),null);
  }finally{
    if(hookMounted)await viewer.evaluate(()=>window.hook.destroyed()).catch(()=>{});
    await browser.close();
  }
});
