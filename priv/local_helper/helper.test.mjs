import test from 'node:test';
import assert from 'node:assert/strict';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium}=await import('../carrefour_browser/node_modules/playwright/index.mjs');
import {createLocalCart} from './cart.mjs';
import {encodeMessage,messageDecoder} from './protocol.mjs';
import {storefront} from '../../test/extension/fixtures.mjs';

test('native messaging handles fragmented frames and rejects oversized messages',()=>{
  const values=[],decode=messageDecoder(value=>values.push(value));
  const frames=Buffer.concat([encodeMessage({action:'open'}),encodeMessage({action:'close'})]);
  for(const byte of frames)decode(Buffer.from([byte]));
  assert.deepEqual(values,[{action:'open'},{action:'close'}]);
  const header=Buffer.alloc(4);header.writeUInt32LE(65537);
  assert.throws(()=>decode(header),/message_too_large/);
});

test('prepares invisibly, opens only on request, restores exact cart without replaying additions',async()=>{
  const launches=[],browsers=[],events=[];
  const plan={store:'carrefour',products:[{id:'42',name:'Milk 500ml',url:'https://www.carrefour.ke/mafken/en/milk/p/42',packs:2,expected_price:'62.00'}]};
  const launch=async headless=>{
    launches.push(headless);
    // Test windows stay headless; the existing browser_handoff suite exercises
    // actual headed browsers. Use real context storage and exact cart checks.
    const browser=await chromium.launch({headless:true,channel:'chromium'});
    const createContext=browser.newContext.bind(browser);
    browser.newContext=async options=>{
      const context=await createContext(options);
      await context.route('https://www.carrefour.ke/**',route=>route.fulfill({contentType:'text/html',body:storefront('carrefour')}));
      return context;
    };
    browsers.push(browser);return browser;
  };
  const cart=await createLocalCart({plan,launch,emit:event=>events.push(event)});
  try {
    await cart.prepare();
    assert.deepEqual(launches,[true]);
    assert.equal(events.at(-1).status,'ready');
    assert.equal(await browsers[0].contexts()[0].pages()[0].evaluate(()=>localStorage.getItem('qty')),'2');
    await cart.open();
    assert.deepEqual(launches,[true,false]);
    assert.equal(await browsers[1].contexts()[0].pages()[0].evaluate(()=>localStorage.getItem('qty')),'2');
    assert.equal(browsers[0].isConnected(),false);
    await cart.open();
    assert.deepEqual(launches,[true,false]);
  } finally {await cart.close();}
});

test('retries a protocol failure only for page navigation',async()=>{
  const {navigateCartPage}=await import('./cart.mjs');
  let reads=0;
  await navigateCartPage({goto:async()=>{if(++reads===1)throw Error('NS_ERROR_NET_HTTP3_PROTOCOL_ERROR');return {ok:()=>true};}},'https://www.carrefour.ke/mafken/en/app/cart');
  assert.equal(reads,2);
  reads=0;
  await assert.rejects(navigateCartPage({goto:async()=>{reads++;throw Error('store_access_denied');}},'https://www.carrefour.ke/mafken/en/app/cart'));
  assert.equal(reads,1);
});

test('shows the actual Carrefour price error and never opens a window on failure',async()=>{
  const events=[],launches=[];
  const plan={store:'carrefour',products:[{id:'42',name:'Butter',url:'https://www.carrefour.ke/butter/p/42',packs:3,expected_price:'60.00'}]};
  const launch=async headless=>{
    launches.push(headless);
    const browser=await chromium.launch({headless:true,channel:'chromium'});
    const newContext=browser.newContext.bind(browser);
    browser.newContext=async options=>{const context=await newContext(options);await context.route('https://www.carrefour.ke/**',route=>route.fulfill({contentType:'text/html',body:storefront('carrefour')}));return context;};
    return browser;
  };
  const cart=await createLocalCart({plan,launch,emit:event=>events.push(event)});
  try {
    await cart.prepare();
    assert.deepEqual(launches,[true]);
    assert.equal(events.at(-1).status,'attention');
    assert.match(events.at(-1).message,/price changed for Butter/);
    assert.ok(events.every(event=>!/headless|preparing.*browser/i.test(event.message)));
  } finally {await cart.close();}
});
