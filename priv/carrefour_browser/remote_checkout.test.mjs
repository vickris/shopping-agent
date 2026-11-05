import test from 'node:test';
import assert from 'node:assert/strict';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium, firefox} = await import('playwright');
const {remoteCheckout} = await import('./remote_checkout.mjs');
const {publicAddress, publicURL, restrictNetwork} = await import('./public_network.mjs');

for (const [name, engine] of [['chromium',chromium],['firefox',firefox]]) {
  test(`${name}: checkout retains cart, edits fields, switches payment tabs, isolates shoppers`, async () => {
    const browser = await engine.launch({headless:true, ...(name === 'chromium' ? {channel:'chromium'} : {})});
    try {
      const context = await browser.newContext({viewport:{width:1024,height:768}});
      await context.route('https://shop.test/**', route => route.fulfill({contentType:'text/html',body:`
        <input id="address" style="position:absolute;left:10px;top:10px;width:300px;height:50px">
        <button style="position:absolute;left:10px;top:80px" onclick="localStorage.setItem('cart','prepared');window.open('/payment')">Review payment</button>
        <div style="height:2000px">Checkout</div>`}));
      const page = await context.newPage();
      await page.goto('https://shop.test/checkout');
      await page.evaluate(() => { localStorage.setItem('cart','prepared'); sessionStorage.setItem('branch','nearby'); });
      const remote = remoteCheckout(() => page);
      const frame = await remote({type:'frame'});
      assert.ok(frame.image.length > 100);
      assert.equal(frame.width,1024);
      await remote({type:'click',x:30,y:30});
      await remote({type:'text',text:'Demo address'});
      await remote({type:'key',key:'Backspace'});
      assert.equal(await page.locator('#address').inputValue(),'Demo addres');
      assert.equal(await page.evaluate(()=>localStorage.getItem('cart')),'prepared');
      assert.equal(await page.evaluate(()=>sessionStorage.getItem('branch')),'nearby');
      const opened = context.waitForEvent('page');
      await remote({type:'click',x:40,y:90});
      const popup = await opened;
      await popup.waitForLoadState();
      const tabs = await remote({type:'frame'});
      assert.equal(tabs.tabs.length,2);
      assert.equal((await remote({type:'tab',index:1})).active,1);
      assert.equal(await popup.evaluate(()=>localStorage.getItem('cart')),'prepared');
      const other = await browser.newContext();
      await other.route('https://shop.test/**',route=>route.fulfill({body:'Other shopper'}));
      const otherPage=await other.newPage();await otherPage.goto('https://shop.test/');
      assert.equal(await otherPage.evaluate(()=>localStorage.getItem('cart')),null);
      await assert.rejects(remote({type:'key',key:'F12'}),/invalid_input/);
      await assert.rejects(remote({type:'click',x:-1,y:20}),/invalid_input/);
      await assert.rejects(remote({type:'text',text:'x'.repeat(2049)}),/invalid_input/);
      const dialogAppeared = page.waitForEvent('dialog');
      const promptResult = page.evaluate(() => prompt('Enter the demo verification code'));
      await dialogAppeared;
      const dialogFrame = await remote({type:'frame'});
      assert.deepEqual(dialogFrame.dialog,{type:'prompt',message:'Enter the demo verification code'});
      await remote({type:'dialog',choice:'accept',text:'123456'});
      assert.equal(await promptResult,'123456');
      const originalPages = context.pages().length;
      await assert.rejects(remote({type:'navigate',url:'http://localhost/'}),/invalid_input/);
      assert.equal(context.pages().length,originalPages);
      await other.close();
    } finally {await browser.close();}
  });
}

test('remote browser networking rejects private addresses and mixed DNS results',async()=>{
  for(const ip of ['127.0.0.1','10.1.2.3','172.16.1.1','192.168.1.1','169.254.169.254','100.64.0.1','::1','fc00::1','::ffff:127.0.0.1']) assert.equal(publicAddress(ip),false,ip);
  assert.equal(publicAddress('8.8.8.8'),true);
  assert.equal(publicAddress('2606:4700:4700::1111'),true);
  for(const url of ['http://example.com','https://localhost','https://service.internal','https://127.0.0.1','https://[::1]','file:///etc/passwd','https://shop.test:444/']) assert.equal(await publicURL(url),false,url);
  assert.equal(await publicURL('https://shop.test',async()=>[{address:'8.8.8.8'}]),true);
  assert.equal(await publicURL('https://shop.test',async()=>[{address:'8.8.8.8'},{address:'10.0.0.1'}]),false);
  const routes=[];let aborted=false;
  await restrictNetwork({route:async(_,fn)=>routes.push(fn),routeWebSocket:async()=>{}});
  await routes[0]({request:()=>({url:()=> 'http://169.254.169.254/latest/meta-data/'}),abort:async()=>{aborted=true;},continue:()=>{throw Error('private request allowed');}});
  assert.equal(aborted,true);
});
