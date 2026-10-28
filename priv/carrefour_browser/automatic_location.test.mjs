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

const carrefourFixture=`
  <header><button onclick="document.querySelector('#address').hidden=false">Westlands<img src="Caret_Down_Arrow_for_address_location.svg"></button></header>
  <section id="address" hidden><input id="pac-input-add-address" class="pac-target-input"><div class="pac-item" onclick="window.wrongLocation=true">Far Road, Kenya</div><div class="pac-item" onclick="document.querySelector('#address').hidden=true;document.querySelector('#confirm').hidden=false;document.querySelector('#cookie').hidden=false">Nearby Road, Kenya</div></section>
  <div role="dialog" aria-label="Confirm delivery location" id="confirm" hidden><button onclick="document.querySelector('header button').firstChild.textContent='Nearby Road, Kenya';document.querySelector('#confirm').hidden=true">Yes, deliver to this location</button></div>
  <div id="cookie" hidden style="position:fixed;inset:0;z-index:9999;background:white"><button onclick="document.querySelector('#cookie').hidden=true">Accept All Cookies</button></div>
  <script>window.google={maps:{Geocoder:class {async geocode(request){const far=request.address?.includes('Far');return {results:[{formatted_address:'Nearby Road, Kenya',types:['route'],geometry:{location:{lat:()=>far?-1.2:-1.367,lng:()=>far?36.8:36.936}}}]}}}}};</script>`;

test('Carrefour resolves its own map address and confirms through the UI', () => fixture('https://www.carrefour.ke/', carrefourFixture, async page => {
    assert.equal((await selectAutomaticLocation(page, 'carrefour', point)).confirmation, 'geolocation');
    assert.equal(await page.locator('#pac-input-add-address').inputValue(), 'Nearby Road, Kenya');
    assert.equal(await page.evaluate(() => Boolean(window.wrongLocation)), false);
}));

test('Carrefour falls back from an unmatched premise to a nearby street',()=>fixture('https://www.carrefour.ke/',carrefourFixture,async page=>{
  await page.evaluate(()=>{
    const Original=google.maps.Geocoder;
    google.maps.Geocoder=class extends Original {async geocode(request){
      const response=await super.geocode(request);
      if(request.location)return {results:[{...response.results[0],formatted_address:'Unmatched Premise',types:['premise']},response.results[0]]};
      if(document.querySelector('input').value==='Unmatched Premise')response.results[0].geometry.location={lat:()=>-1.2,lng:()=>36.8};
      return response;
    }};
  });
  assert.equal((await selectAutomaticLocation(page,'carrefour',point)).confirmation,'geolocation');
  assert.equal(await page.locator('input').inputValue(),'Nearby Road, Kenya');
}));

test('Carrefour supports a plus-code address when no street result is available',()=>fixture('https://www.carrefour.ke/',carrefourFixture,async page=>{
  await page.evaluate(()=>{
    const Original=google.maps.Geocoder;
    google.maps.Geocoder=class extends Original {async geocode(request){const response=await super.geocode(request);if(request.location){response.results[0].formatted_address='6WPH+FP Syokimau, Kenya';response.results[0].types=['plus_code'];}return response;}};
  });
  assert.equal((await selectAutomaticLocation(page,'carrefour',point)).confirmation,'geolocation');
  assert.equal(await page.locator('input').inputValue(),'6WPH+FP Syokimau, Kenya');
}));

test('Carrefour dismisses a cookie banner that appears during address lookup',()=>fixture('https://www.carrefour.ke/',carrefourFixture,async page=>{
  await page.evaluate(()=>{
    const Original=google.maps.Geocoder;
    google.maps.Geocoder=class extends Original {async geocode(request){if(request.location)document.querySelector('#cookie').hidden=false;return super.geocode(request);}};
  });
  assert.equal((await selectAutomaticLocation(page,'carrefour',point)).confirmation,'geolocation');
}));

test('Carrefour rechecks suggestions replaced while their addresses are being verified',()=>fixture('https://www.carrefour.ke/',carrefourFixture,async page=>{
  await page.evaluate(()=>{
    document.querySelectorAll('.pac-item')[1].textContent='Old Nearby Road, Kenya';
    const Original=google.maps.Geocoder;
    google.maps.Geocoder=class extends Original {async geocode(request){
      if(request.address?.startsWith('Old Nearby'))document.querySelectorAll('.pac-item')[1].textContent='Nearby Road, Kenya';
      return super.geocode(request);
    }};
  });
  assert.equal((await selectAutomaticLocation(page,'carrefour',point)).confirmation,'geolocation');
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

function naivasFixture(save=true) {
  return `
  <span class="geoLocation">Nairobi, Kenya</span>
  <button data-drawer-show="address_drawer" onclick="document.querySelector('#address_drawer').hidden=false">Change</button>
  <div id="address_drawer" hidden>
    <button onclick="document.querySelector('#form').hidden=false;document.querySelector('#address_drawer').setAttribute('role','dialog')">Add New Address</button>
    <div id="form" hidden><input id="address-input_map_drawer" class="pac-target-input">
    <div class="pac-item" onclick="window.selected=true">Nearby Road, Kenya</div>
    <button onclick="if(window.selected && ${save}){localStorage.setItem('address','Nearby Road, Kenya');document.querySelector('.geoLocation').textContent='Nearby Road, Kenya';}document.querySelector('#address_drawer').hidden=true;document.querySelector('#address_drawer').removeAttribute('role')">Save Address</button></div>
  </div>
  <script>
    window.Livewire={find:()=>({get:key=>window.selected?(key==='latitude'?-1.367:36.936):null})};window.Alpine={};
    document.querySelector('.geoLocation').textContent=localStorage.getItem('address')||'Nairobi, Kenya';
    window.google={maps:{Geocoder:class {async geocode(request){const far=request.address==='Nairobi, Kenya';return {results:[{formatted_address:'Nearby Road, Kenya',types:['route'],geometry:{location:{lat:()=>far?-1.28:-1.367,lng:()=>far?36.8:36.936}}}]}}}}};
  </script>`;
}

test('Naivas selects a nearby address, saves it and verifies persistence without an override',()=>fixture('https://www.naivas.online/',naivasFixture(),async page=>{
  const result=await selectAutomaticLocation(page,'naivas',point,async url=>{assert.equal(new URL(url).pathname,'/search');await page.reload();});
  assert.equal(result.label,'Nearby Road, Kenya');
  assert.equal(result.confirmation,'geolocation');
}));

test('Naivas ignores suggestions covered by a duplicate autocomplete overlay',()=>fixture('https://www.naivas.online/',naivasFixture(),async page=>{
  await page.evaluate(()=>{
    const item=document.querySelector('.pac-item');
    item.style.cssText='position:absolute;left:200px;top:200px;width:300px;height:40px;z-index:2;background:white';
    const covered=item.cloneNode(true);covered.style.zIndex='1';
    covered.setAttribute('onclick','window.wrongLocation=true');
    item.before(covered);
  });
  assert.equal((await selectAutomaticLocation(page,'naivas',point)).confirmation,'geolocation');
  assert.equal(await page.evaluate(()=>Boolean(window.wrongLocation)),false);
}));

test('Naivas waits for asynchronous map coordinates before saving',()=>fixture('https://www.naivas.online/',naivasFixture(),async page=>{
  await page.evaluate(()=>{
    document.querySelector('.pac-item').setAttribute('onclick','window.selected=true;setTimeout(()=>window.nativeReady=true,300)');
    window.Livewire.find=()=>({get:key=>window.nativeReady?(key==='latitude'?-1.367:36.936):null});
    const save=Array.from(document.querySelectorAll('button')).find(b=>b.textContent==='Save Address');
    save.setAttribute('onclick','if(!window.nativeReady)window.savedTooEarly=true;'+save.getAttribute('onclick'));
  });
  assert.equal((await selectAutomaticLocation(page,'naivas',point)).confirmation,'geolocation');
  assert.equal(await page.evaluate(()=>Boolean(window.savedTooEarly)),false);
}));

test('Naivas can report the abbreviated street of a geocoded premise',()=>fixture('https://www.naivas.online/',naivasFixture(),async page=>{
  await page.evaluate(()=>{
    const Original=google.maps.Geocoder;
    google.maps.Geocoder=class extends Original {async geocode(request){const result=await super.geocode(request);if(request.location)result.results[0].formatted_address='Health Centre, Nearby Road, Kenya';return result;}};
    const save=Array.from(document.querySelectorAll('button')).find(b=>b.textContent==='Save Address');
    save.setAttribute('onclick',save.getAttribute('onclick').replace("textContent='Nearby Road, Kenya'","textContent='Nearby Road'"));
  });
  assert.equal((await selectAutomaticLocation(page,'naivas',point)).label,'Nearby Road');
}));

test('Naivas accepts a short saved neighbourhood name after verifying map coordinates',()=>fixture('https://www.naivas.online/',naivasFixture(),async page=>{
  await page.evaluate(()=>{
    const Original=google.maps.Geocoder;
    google.maps.Geocoder=class extends Original {async geocode(request){const response=await super.geocode(request);if(request.location)response.results[0].formatted_address='Ruaka, Kenya';return response;}};
    const save=Array.from(document.querySelectorAll('button')).find(b=>b.textContent==='Save Address');
    save.setAttribute('onclick',save.getAttribute('onclick').replace("textContent='Nearby Road, Kenya'","textContent='Ruaka'"));
  });
  assert.equal((await selectAutomaticLocation(page,'naivas',point)).label,'Ruaka');
}));

test('Naivas never marks its unchanged default location as automatically confirmed',()=>fixture('https://www.naivas.online/',naivasFixture(false),async page=>{
  await assert.rejects(selectAutomaticLocation(page,'naivas',point),/location_not_saved/);
}));

test('homepage resolves location on entry without waiting for a button click',async()=>{
  const source=await readFile(new URL('../../assets/js/location.js',import.meta.url),'utf8');
  await fixture('https://shop.test/','<div id="location" data-auto-location><button data-use-location>Refresh my location</button><p data-location-progress></p></div>',async page=>{
    await page.evaluate(async source=>{
      const {BrowserLocation}=await import('data:text/javascript,'+encodeURIComponent(source));
      window.events=[];
      BrowserLocation.mounted.call({el:document.querySelector('#location'),pushEvent:(name,data,done)=>{window.events.push({name,data});done?.();}});
    },source);
    await page.waitForFunction(()=>window.events.length===1);
    assert.deepEqual(await page.evaluate(()=>window.events),[{name:'location-detected',data:point}]);
    assert.equal(await page.evaluate(()=>localStorage.length),0);
  });
});

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
