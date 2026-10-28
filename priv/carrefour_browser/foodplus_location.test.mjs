import test from 'node:test';
import assert from 'node:assert/strict';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium}=await import('playwright');
const {selectAutomaticLocation}=await import('./automatic_location.mjs');
const {readLocation}=await import('./delivery_location.mjs');
const {cartFailure}=await import('./cart_errors.mjs');
const {prepareStore,verifyStoreCart}=await import('./store_carts.mjs');
const point={latitude:-1.4271152,longitude:36.9763846,accuracy:100};

async function fixture(run,{saved='The Stop @Rhapta Branch',resolver='The Stop @Rhapta Branch',retained=saved}={}) {
  const browser=await chromium.launch({headless:true,channel:'chromium'});
  try {
    const page=await browser.newPage();
    let navigations=0,queries=[];
    await page.route('https://foodplus.co.ke/**',async route=>{
      const url=new URL(route.request().url());
      if(url.pathname.startsWith('/rest/')) {
        queries.push(url.searchParams);
        return route.fulfill({json:{success:true,availableStores:[{StoreName:resolver,isSelected:1,storeCode:'stop_rhapta'}]}});
      }
      navigations++;
      const label=navigations>1?retained:saved;
      await route.fulfill({contentType:'text/html',body:`<div id="switcher-store-trigger"><strong><span>Main Website Store</span></strong></div>
        <div id="store-popup"><button data-role="use-location" onclick="document.querySelector('#switcher-store-trigger span').textContent='${label}';this.parentElement.remove()">Use my location</button></div>`});
    });
    await page.goto('https://foodplus.co.ke/catalogsearch/result/?q=milk');
    await run(page,queries);
  } finally {await browser.close();}
}

test('Foodplus native location selection is verified against the GPS resolver and retained',()=>fixture(async(page,queries)=>{
  const result=await selectAutomaticLocation(page,'foodplus',point,async url=>{
    await page.goto(url);
    await page.getByRole('button',{name:'Use my location'}).click();
  });
  assert.deepEqual(result,{label:'The Stop @Rhapta Branch',confirmation:'geolocation'});
  assert.equal(Number(queries[0].get('lattitude')),point.latitude);
  assert.equal(Number(queries[0].get('longitude')),point.longitude);
}));

test('Foodplus rejects an unrelated saved branch',()=>fixture(async page=>{
  await assert.rejects(selectAutomaticLocation(page,'foodplus',point,()=>{}),/location_not_saved/);
},{resolver:'Different branch'}));

test('Foodplus rejects a branch lost after navigation',()=>fixture(async page=>{
  await assert.rejects(selectAutomaticLocation(page,'foodplus',point,async url=>{
    await page.goto(url);
    await page.getByRole('button',{name:'Use my location'}).click();
  }),/location_not_saved/);
},{retained:'Other branch'}));

test('Foodplus default catalogue is never a confirmed branch',()=>fixture(async page=>{
  await assert.rejects(readLocation(page,'foodplus'),/location_unconfirmed/);
}));

test('Foodplus checkout is explicitly unavailable, never routed to Naivas cart controls',async()=>{
  const args={plan:{store:'foodplus'}};
  await assert.rejects(prepareStore(args),/checkout_unavailable/);
  await assert.rejects(verifyStoreCart(args),/checkout_unavailable/);
  assert.equal(cartFailure(Error('checkout_unavailable')).error,'checkout_unavailable');
});
