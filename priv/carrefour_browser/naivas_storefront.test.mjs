import test from 'node:test';
import assert from 'node:assert/strict';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium}=await import('playwright');
import {waitForNaivasSearch,naivasSearchURL} from './naivas_storefront.mjs';
test('React readiness handles adjacent filter text without mistaking 170 results for zero',async()=>{
  const browser=await chromium.launch({headless:true,channel:'chromium'});
  try {
    const page=await browser.newPage();
    await page.setContent('<main><span>Offers</span><span>170 Result(s)</span></main>');
    setTimeout(()=>page.evaluate(()=>document.querySelector('main').insertAdjacentHTML('beforeend','<div class="group"><p class="line-clamp-2">Milk</p></div>')),150);
    await waitForNaivasSearch(page);
    assert.equal(await page.locator('p').innerText(),'Milk');
    await page.setContent('<main><span>Offers</span><span>0 Result(s)</span></main>');
    await waitForNaivasSearch(page);
    assert.equal(naivasSearchURL('milk & cream'),'https://www.naivas.online/search?q=milk%20%26%20cream');
  } finally {await browser.close();}
});
