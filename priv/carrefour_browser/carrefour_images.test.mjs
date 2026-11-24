import test from 'node:test';
import assert from 'node:assert/strict';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium}=await import('playwright');
import {loadCarrefourImages} from './carrefour_images.mjs';

test('captures delayed and offscreen Carrefour images without requiring image downloads',async()=>{
  const browser=await chromium.launch({headless:true,channel:'chromium'});
  try {
    const page=await browser.newPage();
    await page.setContent(`<style>.group{height:900px}</style>${[1,2,3].map(id=>`<div class="group"><a href="/p/${id}"><span class="line-clamp-2">Milk ${id}</span></a></div>`).join('')}
      <script>const observer=new IntersectionObserver(entries=>{for(const {target,isIntersecting} of entries)if(isIntersecting){setTimeout(()=>{if(!target.querySelector('img'))target.insertAdjacentHTML('beforeend','<img alt="Product image" src="https://images.invalid/'+target.querySelector('a').getAttribute('href').split('/').pop()+'.jpg">')},100);}});document.querySelectorAll('.group').forEach(card=>observer.observe(card));</script>`);
    await loadCarrefourImages(page);
    assert.equal(await page.locator('img[alt="Product image"]').count(),3);
    await page.setContent('<div class="group"><a href="/p/4"><span class="line-clamp-2">No image</span></a></div>');
    await loadCarrefourImages(page,{timeout:100});
    assert.equal(await page.locator('img').count(),0);
  } finally {await browser.close();}
});
