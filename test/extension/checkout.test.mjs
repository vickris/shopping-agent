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
  const offerPlan=basePlan();offerPlan.products[0].url+='?offer=retail&sellerId=1&sid=store#details';
  const offered=validatePlan(offerPlan).products[0].url;
  assert.ok(offered.includes('sellerId=1'));assert.ok(offered.includes('offer=retail'));assert.equal(new URL(offered).hash,'');
  assert.equal(appOrigin('https://deal-agent-beta.onrender.com/'),true);
  assert.equal(appOrigin('https://evil.test'),false);
  assert.equal(storeURL('https://www.quickmart.co.ke/milk','carrefour'),false);
  for(const change of [{created_at:1},{created_at:Math.floor(Date.now()/1000)+10000},{store:'other'},{version:2},{extra:'x'.repeat(65536)}])assert.throws(()=>validatePlan({...basePlan(),...change}));
  for(const change of [{url:'https://evil.test/p/42'},{url:'https://www.carrefour.ke/mafken/en/milk/p/42?token=secret'},{packs:0},{packs:51},{expected_price:'NaN'},{url:'https://user:pass@www.carrefour.ke/p/42'}]){
    const plan=basePlan();Object.assign(plan.products[0],change);assert.throws(()=>validatePlan(plan));
  }
  const plan=basePlan();plan.products.push(plan.products[0]);assert.throws(()=>validatePlan(plan));
  assert.equal('cookies' in validatePlan({...basePlan(),cookies:'never-export'}),false);
});

for(const store of ['carrefour','quickmart','naivas']) {
  test(`${store}: native basket is idempotent, keeps browser session, never pays`,async()=>{
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
      await context.route(`https://${host}/**`,route=>route.fulfill({contentType:'text/html',body:storefront(store,{price:'99.00'})}));
      await page.goto(url);
      await page.evaluate(()=>set(0));
      assert.match((await page.evaluate(cartStep,{store,product,products:[product],phase:'items',branch:'73'})).error,/price changed/);
      assert.equal(await page.evaluate(()=>localStorage.getItem('qty')),'0');
    }finally{await browser.close();}
  });
}
