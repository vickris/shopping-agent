import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium}=await import('playwright');
import {prepareStore,verifyStoreCart} from './store_carts.mjs';
import {readLocation} from './delivery_location.mjs';
import {naivasReact} from '../../test/extension/fixtures.mjs';
const cents=value=>BigInt(String(value).replace('.',''));
const plan={store:'naivas',estimated_total:'186.00',products:[{id:'42',name:'Milk 500ml',url:'https://www.naivas.online/milk',query:'milk',packs:3,expected_price:'62.00'}]};

test('server and extension use identical storefront controls',async()=>{
  assert.equal(await readFile(new URL('../../extension/adapters.js',import.meta.url),'utf8'),await readFile(new URL('./storefront_steps.mjs',import.meta.url),'utf8'));
});

test('saved Naivas address proceeds through server cart preparation and checkout without a helper',async()=>{
  const browser=await chromium.launch({headless:true,channel:'chromium'});
  try {
    const page=await browser.newPage(),events=[];
    await page.route('https://www.naivas.online/**',route=>route.fulfill({contentType:'text/html',body:naivasReact()}));
    const navigate=async url=>{await page.goto(url);assert.equal((await readLocation(page,'naivas')).label,'Gateway Mall');};
    const result=await prepareStore({page,plan,navigate,cents,emit:event=>events.push(event)});
    assert.equal(result.status,'ready');assert.equal(result.verified,true);
    assert.equal(await page.evaluate(()=>localStorage.getItem('qty')),'3');
    assert.equal(await page.evaluate(()=>localStorage.getItem('extra')),'0');
    assert.equal(await page.evaluate(()=>localStorage.getItem('paid')),null);
    // An open cart drawer must not be mistaken for an incomplete address form.
    assert.equal((await readLocation(page,'naivas')).label,'Gateway Mall');
    await verifyStoreCart({page,plan,cents});
    assert.equal(events.length,1);assert.match(events[0].message,/Adding Milk/);
    assert.equal(browser.contexts()[0].pages().length,1);
  } finally {await browser.close();}
});

test('Naivas refuses cart preparation before an address is saved',async()=>{
  const browser=await chromium.launch({headless:true,channel:'chromium'});
  try {
    const page=await browser.newPage();
    await page.route('https://www.naivas.online/**',route=>route.fulfill({contentType:'text/html',body:naivasReact({address:'Nairobi, Kenya'})}));
    await assert.rejects(prepareStore({page,plan,navigate:url=>page.goto(url),cents,emit:()=>{}}),/location_unconfirmed/);
    assert.equal(await page.evaluate(()=>localStorage.getItem('qty')),'0');
    assert.equal(await page.evaluate(()=>localStorage.getItem('extra')),'1');
  } finally {await browser.close();}
});
