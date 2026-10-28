import test, {before, after} from 'node:test';
import assert from 'node:assert/strict';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium} = await import('playwright');
import {cartMatches, verifyCarrefourCart} from './carrefour_cart.mjs';
let browser;
before(async () => { browser = await chromium.launch({headless: true, channel: 'chromium'}); });
after(async () => { await browser?.close(); });
const expected = [{id: '132858', packs: 2, total: '12400'}];
const row = (id = '132858', quantity = 2, total = '124.00') => `<article><a href="https://www.carrefour.ke/mafken/en/p/${id}?sid=SLOTTED">Milk</a><div data-testid="expanded-widget"><button aria-label="Decrease quantity">-</button><span><span>${quantity}</span></span><button aria-label="Increase quantity">+</button></div><div class="items-baseline"><span>KES</span><span>${total}</span></div></article>`;
async function fixture(html, run) {
  const page = await browser.newPage();
  try { await page.setContent(`<main>${html}</main>`); await run(page); } finally { await page.close(); }
}

test('current cart widgets verify SKU, quantity and line price', () => fixture(row(), async page => {
  assert.equal(await page.evaluate(cartMatches, expected), true);
}));
for (const [name, html] of [
  ['wrong quantity', row('132858', 1)],
  ['wrong SKU', row('999')],
  ['extra product', row() + row('999')],
  ['duplicate SKU', row() + row()],
  ['changed total', row('132858', 2, '125.00')]
]) test(`rejects ${name}`, () => fixture(html, async page => {
  assert.equal(await page.evaluate(cartMatches, expected), false);
}));

test('recommendation widgets do not count as cart rows', () => fixture(row() + `<div class="group">${row('999')}</div>`, async page => {
  assert.equal(await page.evaluate(cartMatches, expected), true);
}));
test('legacy cart dropdowns still verify exact quantities', () => fixture('<div id="entries-1"><div class="relative rounded-xl"><a href="https://www.carrefour.ke/mafken/en/p/132858?sid=SLOTTED">Milk</a><button role="combobox">2</button></div></div>', async page => {
  assert.equal(await page.evaluate(cartMatches, expected), true);
}));
test('verification waits for hydration and reports mismatch on timeout', () => fixture(row('132858', 1), async page => {
  const products = [{id: '132858', packs: 2, expected_price: '62.00'}];
  const cents = () => 6200n;
  await assert.rejects(verifyCarrefourCart(page, products, cents, 100), /cart_mismatch/);
  await page.evaluate(() => setTimeout(() => {document.querySelector('[data-testid="expanded-widget"] > span > span').textContent = '2';}, 50));
  await verifyCarrefourCart(page, products, cents, 2000);
}));
