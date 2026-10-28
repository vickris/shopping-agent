import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {openBrowserSession} from './browser_handoff.mjs';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium,firefox}=await import('playwright');

for(const [name,engine] of [['chromium',chromium],['firefox',firefox]]) {
  test(`${name}: headless guest cart opens headed with storage intact and no add replay`,async()=>{
    let additions=0;
    const server=http.createServer((req,res)=>{
      if(req.url==='/add')additions++;
      res.setHeader('Content-Type','text/html; charset=utf-8');
      res.end('<main id="cart">Milk × 2 · KES 140</main>');
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const origin=`http://127.0.0.1:${server.address().port}`;
    const options=name==='chromium'?{channel:'chromium'}:{};
    const original=await engine.launch({headless:true,...options});
    let opened;
    try {
      const context=await original.newContext();
      await context.addCookies([{name:'guest',value:'fixture-basket',url:origin,httpOnly:true}]);
      const page=await context.newPage();
      await page.goto(origin+'/cart');
      await page.evaluate(async()=>{
        localStorage.setItem('branch','73');
        sessionStorage.setItem('cart','milk:2');
        await fetch('/add');
      });
      opened=await openBrowserSession({browser:original,page,origin,
        launch:()=>engine.launch({headless:false,...options}),
        verify:async candidate=>{
          assert.equal(await candidate.locator('#cart').innerText(),'Milk × 2 · KES 140');
          assert.deepEqual(await candidate.evaluate(()=>[localStorage.getItem('branch'),sessionStorage.getItem('cart')]),['73','milk:2']);
          assert.equal((await candidate.context().cookies()).find(c=>c.name==='guest')?.value,'fixture-basket');
        }});
      await opened.page.evaluate(()=>sessionStorage.setItem('cart','milk:3'));
      await opened.page.reload();
      assert.equal(await opened.page.evaluate(()=>sessionStorage.getItem('cart')),'milk:3');
      assert.equal(additions,1);
      assert.equal(original.isConnected(),true);
      assert.notEqual(opened.browser,original);
      assert.equal(opened.page.url(),origin+'/cart');
    } finally {
      server.closeAllConnections();
      await opened?.browser.close();await original.close();
      await new Promise(resolve=>server.close(resolve));
    }
  });
}

test('a failed verification closes the new browser and retains the original basket',async()=>{
  const server=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<main>cart</main>');});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const origin=`http://127.0.0.1:${server.address().port}`;
  const original=await chromium.launch({headless:true,channel:'chromium'});
  let candidate;
  try {
    const page=await original.newPage();await page.goto(origin);
    await assert.rejects(openBrowserSession({browser:original,page,origin,
      launch:async()=>candidate=await chromium.launch({headless:false,channel:'chromium'}),
      verify:async()=>{throw Error('cart_mismatch');}}),/cart_mismatch/);
    assert.equal(candidate.isConnected(),false);
    assert.equal(original.isConnected(),true);
    assert.equal(await page.locator('main').innerText(),'cart');
  } finally {server.closeAllConnections();await original.close();await new Promise(resolve=>server.close(resolve));}
});
