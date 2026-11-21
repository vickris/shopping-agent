import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../priv/carrefour_browser/package.json',import.meta.url));
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium}=require('playwright');
const {cartStep}=await import('../../extension/adapters.js');
const {validatePlan,appOrigin,storeURL}=await import('../../extension/policy.js');
const {storefront}=await import('./fixtures.mjs');
const basePlan=()=>({version:1,request_id:'test-request-id-123456',created_at:Math.floor(Date.now()/1000),store:'carrefour',products:[{id:'42',name:'Milk 500ml',url:'https://www.carrefour.ke/mafken/en/milk/p/42',query:'milk',packs:2,expected_price:'62.00'}]});

test('basket validation restricts origins, products, quantities, expiry and payload size',()=>{
  assert.equal(validatePlan(basePlan()).products.length,1);
  assert.equal(validatePlan({...basePlan(),version:2}).version,2);
  assert.equal(validatePlan({...basePlan(),version:3}).version,3);
  const offerPlan=basePlan();offerPlan.products[0].url+='?offer=retail&sellerId=1&sid=store#details';
  const offered=validatePlan(offerPlan).products[0].url;
  assert.ok(offered.includes('sellerId=1'));assert.ok(offered.includes('offer=retail'));assert.equal(new URL(offered).hash,'');
  assert.equal(appOrigin('https://deal-agent-beta.onrender.com/'),true);
  assert.equal(appOrigin('https://evil.test'),false);
  assert.equal(storeURL('https://www.quickmart.co.ke/milk','carrefour'),false);
  for(const change of [{created_at:1},{created_at:Math.floor(Date.now()/1000)+10000},{store:'other'},{version:4},{extra:'x'.repeat(65536)}])assert.throws(()=>validatePlan({...basePlan(),...change}));
  for(const change of [{url:'https://evil.test/p/42'},{url:'https://www.carrefour.ke/mafken/en/milk/p/42?token=secret'},{packs:0},{packs:51},{expected_price:'NaN'},{url:'https://user:pass@www.carrefour.ke/p/42'}]){
    const plan=basePlan();Object.assign(plan.products[0],change);assert.throws(()=>validatePlan(plan));
  }
  const plan=basePlan();plan.products.push(plan.products[0]);assert.throws(()=>validatePlan(plan));
  assert.equal('cookies' in validatePlan({...basePlan(),cookies:'never-export'}),false);
});

test('reported Carrefour milk and water links validate together without changing offers',()=>{
  const plan=basePlan();
  plan.products=[
    ['81030','uht-milk-full-fat/lato-fino-uht-milk-500ml'],
    ['17396','still-water/quencher-life-premium-water-nrb10l']
  ].map(([id,path])=>({...plan.products[0],id,url:`https://www.carrefour.ke/mafken/en/${path}/p/${id}?offer=offer_carrefour_&sid=SLOTTED&sellerId=0000`}));
  assert.deepEqual(validatePlan(plan).products,plan.products);
  const mismatch=structuredClone(plan);mismatch.products[0].id='999';
  assert.throws(()=>validatePlan(mismatch),/999: product ID does not match/);
  const unsupported=structuredClone(plan);unsupported.products[0].url+='&token=private';
  assert.throws(()=>validatePlan(unsupported),/81030: unsupported URL parameters/);
});

for(const store of ['carrefour','quickmart','naivas']) {
  test(`${store}: fresh cart removes old items, verifies exact contents and never pays`,async()=>{
    const browser=await chromium.launch({headless:true,channel:'chromium'});
    try{
      const host={carrefour:'www.carrefour.ke',quickmart:'www.quickmart.co.ke',naivas:'www.naivas.online'}[store];
      const context=await browser.newContext();
      await context.addCookies([{name:'normal-login',value:'fixture',domain:host,path:'/'}]);
      await context.route(`https://${host}/**`,route=>route.fulfill({contentType:'text/html',body:storefront(store,{extra:true})}));
      const page=await context.newPage();
      const url=store==='carrefour'?`https://${host}/mafken/en/milk/p/42`:store==='quickmart'?`https://${host}/shops/products/73/keyword-milk`:`https://${host}/search?term=milk`;
      const product={id:'42',name:'Milk 500ml',packs:2,expected_price:'62.00',query:'milk',url:store==='carrefour'?url:`https://${host}/milk`};
      await page.goto(url);
      for(let repeat=0;repeat<2;repeat++) {
        await page.evaluate(cartStep,{store,phase:'probe'});
        await page.evaluate(cartStep,{store,product,products:[product],phase:'items',branch:'73'});
        await page.evaluate(cartStep,{store,product,products:[product],phase:'verify',branch:'73'});
        assert.equal(await page.evaluate(()=>localStorage.getItem('qty')),'2');
      }
      await page.evaluate(()=>set(4));
      await page.evaluate(cartStep,{store,product,products:[product],phase:'items',branch:'73'});
      await page.evaluate(cartStep,{store,product,products:[product],phase:'verify',branch:'73'});
      assert.equal(await page.evaluate(()=>localStorage.getItem('qty')),'2');
      assert.equal(await page.evaluate(()=>localStorage.getItem('paid')),null);
      assert.equal((await context.cookies()).find(c=>c.name==='normal-login').value,'fixture');
      const cartURL=store==='carrefour'?`https://${host}/mafken/en/app/cart`:store==='naivas'?`https://${host}/cart/index`:url;
      await page.goto(cartURL);
      assert.equal((await page.evaluate(cartStep,{store,product,products:[product],phase:'verify',exact:true,branch:'73'})).error?.includes('extra products'),true);
      assert.equal((await page.evaluate(cartStep,{store,product,phase:'clear',branch:'73'})).ok,true);
      assert.equal(await page.evaluate(()=>localStorage.getItem('qty')),'0');
      assert.equal(await page.evaluate(()=>localStorage.getItem('extra')),'0');
      assert.equal((await page.evaluate(cartStep,{store,product,phase:'clear',branch:'73'})).ok,true);
      assert.equal(await page.evaluate(()=>localStorage.getItem('paid')),null);
      await context.route(`https://${host}/**`,route=>route.fulfill({contentType:'text/html',body:storefront(store,{price:'99.00'})}));
      await page.goto(url);
      await page.evaluate(()=>set(0));
      assert.match((await page.evaluate(cartStep,{store,product,products:[product],phase:'items',branch:'73'})).error,/price changed/);
      assert.equal(await page.evaluate(()=>localStorage.getItem('qty')),'0');
    }finally{await browser.close();}
  });
}


test('Carrefour stock limit is reported before the old cart is cleared',async()=>{
  const browser=await chromium.launch({headless:true,channel:'chromium'});
  try {
    const page=await browser.newPage();
    await page.route('https://www.carrefour.ke/**',route=>route.fulfill({contentType:'text/html',body:storefront('carrefour',{max:2,extra:true})}));
    const product={...basePlan().products[0],packs:3};
    await page.goto(product.url);await page.evaluate(()=>set(2));
    const result=await page.evaluate(cartStep,{store:'carrefour',product,phase:'preflight'});
    assert.match(result.error,/currently allows only 2 pack/);
    assert.equal(await page.evaluate(()=>localStorage.getItem('qty')),'2');
    assert.equal(await page.evaluate(()=>localStorage.getItem('extra')),null);
  } finally {await browser.close();}
});

test('app checkout status displays extension progress and actionable errors',async()=>{
  const {readFile}=await import('node:fs/promises');
  const source=await readFile(new URL('../../assets/js/browser_checkout.js',import.meta.url),'utf8');
  const {BrowserCheckout}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  const previousWindow=globalThis.window,previousLocation=globalThis.location;
  let listener,offer;
  globalThis.location={origin:'http://localhost:4000'};
  globalThis.window={addEventListener:(_type,fn)=>{listener=fn;},removeEventListener(){},postMessage(){}};
  const status={textContent:''};
  const hook={el:{dataset:{store:'carrefour'},querySelector:()=>status,querySelectorAll:()=>[],addEventListener(){},removeEventListener(){}},handleEvent:(_event,fn)=>{offer=fn;}};
  try {
    BrowserCheckout.mounted.call(hook);offer({plan:{store:'carrefour',request_id:'progress-test'}});
    listener({source:window,origin:location.origin,data:{source:'shopping-agent-extension',type:'basket:progress',request_id:'progress-test',message:'Carrefour currently allows only 2 packs; you selected 3.'}});
    assert.match(status.textContent,/currently allows only 2 packs/);
    listener({source:window,origin:location.origin,data:{source:'shopping-agent-extension',type:'basket:progress',request_id:'old-order',message:'Old order ready'}});
    assert.match(status.textContent,/currently allows only 2 packs/);
    offer({plan:{version:2,store:'carrefour',request_id:'fresh-order'}});
    listener({source:window,origin:location.origin,data:{source:'shopping-agent-extension',request_id:'fresh-order',version:'0.1.3',error:'Invalid or expired basket.'}});
    assert.match(status.textContent,/version 0.2.0 or newer/);
    listener({source:window,origin:location.origin,data:{source:'shopping-agent-extension',request_id:'fresh-order',version:'0.2.0',type:'basket:progress',message:'Fresh cart verified'}});
    assert.equal(status.textContent,'Fresh cart verified');
    offer({plan:{version:3,store:'carrefour',request_id:'background-order'}});
    listener({source:window,origin:location.origin,data:{source:'shopping-agent-extension',request_id:'background-order',version:'0.2.0',error:'Invalid or expired basket.'}});
    assert.match(status.textContent,/version 0.3.0 or newer/);
  } finally {BrowserCheckout.destroyed.call(hook);globalThis.window=previousWindow;globalThis.location=previousLocation;}
});
