import test, {before, after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium} = await import('playwright');
import {selectAutomaticLocation, distanceMeters} from './automatic_location.mjs';
let browser;
before(async () => { browser = await chromium.launch({headless: true, channel: 'chromium'}); });
after(async () => { await browser?.close(); });
const point = {latitude: -1.367, longitude: 36.936, accuracy: 100};
async function fixture(url, html, run, permissions = ['geolocation']) {
  const context = await browser.newContext({geolocation: point, permissions});
  const page = await context.newPage();
  try { await page.route('**/*', route => route.fulfill({contentType: 'text/html', body: html})); await page.goto(url); await run(page); }
  finally { await context.close(); }
}

test('homepage hook requests browser location once and sends only coordinates', async () => {
  const source = await readFile(new URL('../../assets/js/location.js', import.meta.url), 'utf8');
  await fixture('https://shop.test/', '<div id="location"><button data-use-location>Use my location</button><p data-location-progress></p></div>', async page => {
    await page.evaluate(async source => {
      const {BrowserLocation} = await import('data:text/javascript,' + encodeURIComponent(source));
      window.events = [];
      BrowserLocation.mounted.call({el: document.querySelector('#location'), pushEvent: (name, data, done) => {window.events.push({name, data}); done?.();}});
    }, source);
    await page.getByRole('button', {name: 'Use my location'}).click();
    await page.waitForFunction(() => window.events.length > 0);
    assert.deepEqual(await page.evaluate(() => window.events[0]), {name: 'location-detected', data: point});
    assert.equal(await page.evaluate(() => localStorage.length), 0);
  });
});

test('Carrefour resolves its own map address and confirms through the UI', () => fixture('https://www.carrefour.ke/', `
  <header><button onclick="document.querySelector('#address').hidden=false">Westlands<img src="Caret_Down_Arrow_for_address_location.svg"></button></header>
  <section id="address" hidden><input id="pac-input-add-address" class="pac-target-input"><div class="pac-item" onclick="window.wrongLocation=true">Far Road, Kenya</div><div class="pac-item" onclick="document.querySelector('#address').hidden=true;document.querySelector('#confirm').hidden=false;document.querySelector('#cookie').hidden=false">Nearby Road, Kenya</div></section>
  <div role="dialog" aria-label="Confirm delivery location" id="confirm" hidden><button onclick="document.querySelector('header button').firstChild.textContent='Nearby Road, Kenya';document.querySelector('#confirm').hidden=true">Yes, deliver to this location</button></div>
  <div id="cookie" hidden style="position:fixed;inset:0;z-index:9999;background:white"><button onclick="document.querySelector('#cookie').hidden=true">Accept All Cookies</button></div>
  <script>window.google={maps:{Geocoder:class {async geocode(request){const far=request.address?.includes('Far');return {results:[{formatted_address:'Nearby Road, Kenya',types:['route'],geometry:{location:{lat:()=>far?-1.2:-1.367,lng:()=>far?36.8:36.936}}}]}}}}};</script>`, async page => {
    assert.equal((await selectAutomaticLocation(page, 'carrefour', point)).confirmation, 'geolocation');
    assert.equal(await page.locator('#pac-input-add-address').inputValue(), 'Nearby Road, Kenya');
    assert.equal(await page.evaluate(() => Boolean(window.wrongLocation)), false);
}));

test('Quickmart uses native GPS and the resolver-selected branch', () => fixture('https://www.quickmart.co.ke/home', `
  <span class="js-location-address">Enter your delivery address</span>
  <button onclick="navigator.geolocation.getCurrentPosition(p=>{document.querySelector('.js-location-address').textContent='Nearby location';document.querySelector('#nearest').hidden=false;})">Use My Current Location</button>
  <div id="nearest" hidden>Closest branch <button onclick="document.querySelector('#nearest').hidden=true;document.querySelector('#branch').hidden=false">Continue</button></div>
  <div id="branch" hidden><a class="navigation-link" href="/7701">Nearby Quickmart</a></div>`, async page => {
    const location = await selectAutomaticLocation(page, 'quickmart', point, async url => {
      assert.equal(new URL(url).pathname, '/7701');
      await page.setContent('<span class="js-location-address">Nearby location</span><h6>Nearby Quickmart</h6><a href="/shops/report-spam/73">Report</a>');
    });
    assert.equal(location.branch_id, '73');
    assert.equal(location.confirmation, 'geolocation');
}));

test('Naivas remains explicitly unverified when using browser location', () => fixture('https://www.naivas.online/', '<span class="geoLocation">Nairobi, Kenya</span>', async page => {
  assert.equal((await selectAutomaticLocation(page, 'naivas', point)).confirmation, 'user_override');
}));

test('homepage permission denial sends no coordinates and keeps the button usable', async () => {
  const source = await readFile(new URL('../../assets/js/location.js', import.meta.url), 'utf8');
  await fixture('https://shop.test/', '<div id="location"><button data-use-location>Use my location</button><p data-location-progress></p></div>', async page => {
    await page.context().grantPermissions([], {origin: 'https://shop.test'});
    await page.evaluate(async source => {
      const {BrowserLocation} = await import('data:text/javascript,' + encodeURIComponent(source));
      window.events = [];
      BrowserLocation.mounted.call({el: document.querySelector('#location'), pushEvent: (name, data) => window.events.push({name, data})});
    }, source);
    await page.getByRole('button', {name: 'Use my location'}).click();
    await page.waitForFunction(() => window.events.length > 0);
    assert.deepEqual(await page.evaluate(() => window.events), [{name: 'location-error', data: {reason: 'denied'}}]);
    assert.equal(await page.getByRole('button', {name: 'Use my location'}).isEnabled(), true);
  }, []);
});

test('location distance separates a nearby street from a remote namesake', () => {
  assert.equal(distanceMeters(point, point), 0);
  assert.ok(distanceMeters(point, {latitude: -1.368, longitude: 36.936}) < 2000);
  assert.ok(distanceMeters(point, {latitude: -1.2, longitude: 36.8}) > 2000);
});
