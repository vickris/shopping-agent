import test from 'node:test';
import assert from 'node:assert/strict';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium} = await import('playwright');
const {readLocation, confirmLocation} = await import('./delivery_location.mjs');

async function withPage(run) {
  const browser = await chromium.launch({headless: true, channel: 'chromium'});
  try { await run(await browser.newPage()); } finally { await browser.close(); }
}

test('Quickmart confirmation follows the selected branch from home', async () => withPage(async page => {
  await page.route('https://www.quickmart.co.ke/**', route => route.fulfill({contentType: 'text/html', body: route.request().url().endsWith('/7701')
    ? '<span class="js-location-address">Syokimau, Kenya</span><h6>Quickmart Diamond Biz</h6><a href="/shops/report-spam/73">Report</a>'
    : '<span class="js-location-address">Syokimau, Kenya</span><a class="navigation-link" href="/7701">Quickmart Diamond Biz</a>'}));
  await page.goto('https://www.quickmart.co.ke/home');
  const selected = await confirmLocation(page, 'quickmart', 'Syokimau', undefined, url => page.goto(url));
  assert.equal(selected.branch_id, '73');
  assert.equal(selected.label, 'Syokimau, Kenya');
  assert.equal(new URL(page.url()).pathname, '/7701');
}));

test('Naivas confirmation closes the remaining address drawer after a saved location', async () => withPage(async page => {
  await page.route('https://www.naivas.online/**', route => route.fulfill({contentType: 'text/html', body: `
    <span class="geoLocation" style="display:none">Nairobi, Kenya</span><span class="geoLocation">Syokimau, Kenya</span>
    <div id="address_drawer" role="dialog" aria-hidden="false"><button id="close-address-drawer" onclick="this.parentElement.setAttribute('aria-hidden','true');this.parentElement.removeAttribute('role')">Close</button></div>`}));
  await page.goto('https://www.naivas.online/search?term=milk');
  assert.deepEqual(await confirmLocation(page, 'naivas', 'Syokimau', {label: 'Nairobi, Kenya'}), {label: 'Syokimau, Kenya'});
  assert.equal(await page.locator('#address_drawer').getAttribute('aria-hidden'), 'true');
}));

test('Naivas keeps an unsaved default location unconfirmed', async () => withPage(async page => {
  await page.route('https://www.naivas.online/**', route => route.fulfill({contentType: 'text/html', body: '<span class="geoLocation">Nairobi, Kenya</span>'}));
  await page.goto('https://www.naivas.online/');
  await assert.rejects(confirmLocation(page, 'naivas', 'Syokimau', {label: 'Nairobi, Kenya'}), /location_not_saved/);
}));

test('Quickmart reports a missing branch instead of timing out silently', async () => withPage(async page => {
  await page.route('https://www.quickmart.co.ke/**', route => route.fulfill({contentType: 'text/html', body: '<span class="js-location-address">Syokimau, Kenya</span>'}));
  await page.goto('https://www.quickmart.co.ke/home');
  await assert.rejects(confirmLocation(page, 'quickmart', 'Syokimau'), /branch_not_open/);
  await assert.rejects(readLocation(page, 'quickmart'), /branch_not_open/);
}));
