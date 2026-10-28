import {confirmLocation, readLocation} from './delivery_location.mjs';

// Use the supermarket's own visible location workflow and map provider. Never
// select a default branch when automatic resolution fails.
export async function selectAutomaticLocation(page, store, point, navigate, onProgress=()=>{}) {
  let stage='opening_location';
  const step=value=>{stage=value;onProgress(value);};
  try {
  step('opening_location');
  if (store === 'naivas') {
    await page.getByRole('button', {name:'Close without accepting cookies',exact:true}).click({timeout:2500}).catch(()=>{});
    step('loading_map');
    const input=await openNaivasAddressInput(page);
    const addressInput=page.locator('#address-input_map_drawer:visible');
    await selectNearbyAddress(page,point,input,step);
    step('saving_location');
    // The map callback commits coordinates asynchronously. Saving before those
    // values reach the store produces its 'select a location on the map' error.
    await page.waitForFunction(point=>{
      const el=document.querySelector('#address_drawer');
      const component=window.Livewire?.find?.(el?.getAttribute('wire:id'));
      const latitude=component?.get('latitude'),longitude=component?.get('longitude');
      return latitude!=null && longitude!=null && latitude!=='' && longitude!=='' &&
        Number.isFinite(Number(latitude)) && Number.isFinite(Number(longitude)) &&
        Math.hypot((Number(latitude)-point.latitude)*111320,(Number(longitude)-point.longitude)*111320*Math.cos(point.latitude*Math.PI/180))<=2000;
    },point,{timeout:15000});
    const expectedAddress=await input.inputValue();
    await assertNearbyAddress(page,expectedAddress,point);
    await page.getByRole('button',{name:'Save Address',exact:true}).click();
    await addressInput.waitFor({state:'hidden',timeout:15000});
    await closeNaivasAddressDrawer(page);
    step('verifying_location');
    const selected=await readLocation(page,store);
    // Saving can reload the page and unload its map SDK. Compare the saved
    // display with the already geocoded address, then check persistence.
    const normalize=text=>text.toLowerCase().split(',').map(part=>part.trim()).filter(Boolean).slice(0,2).join(',');
    // Naivas may report an abbreviated street instead of the selected premise.
    // Accept a meaningful prefix of either of the address's first two components,
    // but never its default city label. Coordinates were checked before Save.
    const reported=normalize(selected.label);
    const parts=expectedAddress.split(',');
    const labels=parts.slice(0,2).map((_,index)=>normalize(parts.slice(index).join(',')));
    if(!reported || /^nairobi(?:,kenya)?$/.test(reported))throw Error('location_not_saved');
    if(!labels.some(label=>label.startsWith(reported))) {
      // Naivas can reverse-geocode the same pin to an estate name rather than
      // the selected landmark. Reopen its map without saving another address,
      // verify that alias geographically, then close the unsaved form.
      await openNaivasAddressInput(page);
      await assertNearbyAddress(page,selected.label,point);
      await closeNaivasAddressDrawer(page);
    }
    step('retaining_location');
    if(navigate)await navigate('https://www.naivas.online/search?term=milk');
    const retained=await readLocation(page,store);
    if(JSON.stringify(retained)!==JSON.stringify(selected))throw Error('location_not_saved');
    return {...retained,confirmation:'geolocation'};
  }
  if (store === 'quickmart') {
    await page.getByRole('button', {name: 'Accept Cookies', exact: true}).click({timeout: 2000}).catch(() => {});
    const detect = page.getByRole('button', {name: /Use (My|Your) Current Location/i}).filter({visible: true}).first();
    if (!await detect.count()) await page.locator('.locationButtonJs').first().click();
    await detect.click({timeout: 10000});
    // The store's resolver explicitly offers its closest branch; do not choose
    // a branch by page order or keep the old Ruaka search branch.
    const proceed = page.getByRole('button', {name: 'Continue', exact: true});
    await proceed.waitFor({state: 'visible', timeout: 25000});
    await proceed.click();
    await page.waitForFunction(() => {
      const label = document.querySelector('.js-location-address')?.textContent.trim();
      return label && !/enter your|select (address|location)/i.test(label);
    }, null, {timeout: 10000});
  } else {
    await page.getByRole('button', {name: 'Accept All Cookies', exact: true, includeHidden: true}).click({timeout: 2500}).catch(() => {});
    await page.locator('header button').filter({has: page.locator('img[src*="Caret_Down_Arrow_for_address_location"]')}).click();
    step('loading_map');
    const input = page.locator('#pac-input-add-address.pac-target-input:visible');
    await input.waitFor({state: 'visible', timeout: 20000});
    await selectNearbyAddress(page,point,input,step);
    step('saving_location');
    const deliver = page.getByRole('button', {name: 'Yes, deliver to this location', exact: true});
    await deliver.waitFor({state: 'visible', timeout: 15000});
    // The cookie banner can mount after the address dialog opens. Its controls
    // can be aria-hidden by that dialog while still intercepting real clicks.
    await page.getByRole('button', {name: 'Accept All Cookies', exact: true, includeHidden: true}).click({timeout: 3000}).catch(() => {});
    await deliver.click({timeout: 15000});
    await page.getByRole('dialog', {name: /Confirm delivery location|Add delivery location/i}).waitFor({state: 'hidden', timeout: 15000});
  }
  step('verifying_location');
  const location = await confirmLocation(page, store, 'Near you', undefined, navigate);
  return {...location, confirmation: 'geolocation'};
  } catch(error) {error.locationStage ||= stage;throw error;}
}

async function openNaivasAddressInput(page) {
    await page.waitForFunction(()=>Boolean(window.Livewire && window.Alpine),null,{timeout:15000});
    await page.locator('button[data-drawer-show="address_drawer"]:visible').first().click();
    const addressInput=page.locator('#address-input_map_drawer:visible');
    const add=page.getByRole('button',{name:'Add New Address',exact:true});
    await addressInput.or(add).first().waitFor({state:'visible',timeout:15000});
    if(!await addressInput.isVisible()) {
      try {await add.click({timeout:10000,noWaitAfter:true});}
      catch(error) {if(!await addressInput.isVisible())throw error;}
    }
    const input=page.locator('#address-input_map_drawer.pac-target-input:visible');
    await input.waitFor({state:'visible',timeout:20000});
    await page.waitForFunction(()=>typeof window.google?.maps?.Geocoder==='function',null,{timeout:15000});
    return input;
}

async function closeNaivasAddressDrawer(page) {
    const openDrawer=page.locator('#address_drawer[role="dialog"]:not([aria-hidden="true"])');
    if(await openDrawer.isVisible())await page.locator('#close-address-drawer').click();
    await openDrawer.waitFor({state:'hidden',timeout:5000});
}

async function selectNearbyAddress(page,point,input,step) {
    step('loading_map');
    await page.waitForFunction(()=>typeof window.google?.maps?.Geocoder==='function',null,{timeout:15000});
    step('reverse_geocoding');
    const queries = await page.evaluate(async point => {
      const {results} = await Promise.race([
        new google.maps.Geocoder().geocode({location: {lat: point.latitude, lng: point.longitude}}),
        new Promise((_, reject) => setTimeout(() => reject(Error('map_timeout')), 10000))
      ]);
      const rank=result=>result.formatted_address.includes('+')?3:result.types.some(type=>['street_address','premise'].includes(type))?0:result.types.includes('route')?1:2;
      return [...new Set(results.filter(r=>typeof r.formatted_address==='string' && r.formatted_address.trim()).sort((a,b)=>rank(a)-rank(b)).map(r=>r.formatted_address))].slice(0,3);
    }, point);
    if (!queries.length) throw Error('address_not_found');
    let lastClickError;
    for(const address of queries) {
    step('autocomplete');
    await input.fill(address);
    const predictions = page.locator('.pac-item:visible');
    try {await predictions.first().waitFor({state: 'visible', timeout: 5000});}
    catch {continue;}
    await dismissAddressCookies(page);
    for(let suggestionAttempt=0;suggestionAttempt<2;suggestionAttempt++) {
    if(suggestionAttempt)await page.waitForTimeout(350);
    // Some stores mount duplicate autocomplete overlays. Only choose rows a
    // real click can reach, rather than a covered suggestion behind another list.
    const visibleIndices=await predictions.evaluateAll(els=>els.map((el,index)=>{
      const rect=el.getBoundingClientRect();
      return document.elementFromPoint(rect.left+rect.width/2,rect.top+rect.height/2)?.closest('.pac-item')===el?index:null;
    }).filter(index=>index!==null).slice(0,5));
    const addresses=await predictions.evaluateAll((els,indices)=>indices.map(index=>Array.from(els[index].childNodes).map(node=>node.textContent.trim()).filter(Boolean).join(' ')),visibleIndices);
    step('candidate_geocoding');
    const candidates = await page.evaluate(async ({addresses, point}) => Promise.all(addresses.map(async (address, index) => {
      try {
        const {results} = await Promise.race([
          new google.maps.Geocoder().geocode({address, region: 'KE', bounds: {north: point.latitude + 0.05, south: point.latitude - 0.05, east: point.longitude + 0.05, west: point.longitude - 0.05}}),
          new Promise((_, reject) => setTimeout(() => reject(Error('map_timeout')), 10000))
        ]);
        return results.map(result => ({index, latitude: result.geometry.location.lat(), longitude: result.geometry.location.lng()}));
      } catch { return []; }
    })), {addresses, point});
    // Identically named places can exist in different towns. Compare the
    // suggestions to the supplied coordinates instead of taking the first.
    const nearest = candidates.flat().filter(candidate => Number.isFinite(candidate.latitude) && Number.isFinite(candidate.longitude)).map(candidate => ({...candidate, distance: distanceMeters(point, candidate)})).sort((a, b) => a.distance - b.distance)[0];
    if (!nearest || nearest.distance > 2000) continue;
    step('selecting_address');
    await dismissAddressCookies(page);
    // Autocomplete can replace/reorder its lists while geocoding is in flight.
    // Re-find an exposed row with the exact geocoded label before each click.
    const token='location-'+Date.now();
    for(let attempt=0;attempt<3;attempt++) {
      const found=await predictions.evaluateAll((els,{address,token})=>{
        const el=els.find(el=>{
          const text=Array.from(el.childNodes).map(node=>node.textContent.trim()).filter(Boolean).join(' ');
          const rect=el.getBoundingClientRect();
          return text===address && document.elementFromPoint(rect.left+rect.width/2,rect.top+rect.height/2)?.closest('.pac-item')===el;
        });
        if(!el)return false;
        el.setAttribute('data-deal-location-choice',token);return true;
      },{address:addresses[nearest.index],token});
      if(found) {
        try {await page.locator(`[data-deal-location-choice="${token}"]`).click({timeout:2500});return;}
        catch(error) {lastClickError=error;await page.locator(`[data-deal-location-choice="${token}"]`).evaluateAll(els=>els.forEach(el=>el.removeAttribute('data-deal-location-choice')));}
      }
      await page.waitForTimeout(250);
    }
    }
    }
    throw Error('address_not_found',{cause:lastClickError});
}

async function dismissAddressCookies(page) {
  for(const name of ['Accept All Cookies','Close without accepting cookies']) {
    const button=page.getByRole('button',{name,exact:true,includeHidden:true}).filter({visible:true});
    if(await button.count())await button.first().click({timeout:1500}).catch(()=>{});
  }
}

async function assertNearbyAddress(page,address,point) {
  const candidates=await page.evaluate(async ({address,point})=>{
    const {results}=await Promise.race([
      new google.maps.Geocoder().geocode({address,region:'KE',bounds:{north:point.latitude+0.05,south:point.latitude-0.05,east:point.longitude+0.05,west:point.longitude-0.05}}),
      new Promise((_,reject)=>setTimeout(()=>reject(Error('map_timeout')),10000))
    ]);
    return results.map(r=>({latitude:r.geometry.location.lat(),longitude:r.geometry.location.lng()}));
  },{address,point});
  if(!candidates.some(candidate=>Number.isFinite(candidate.latitude) && Number.isFinite(candidate.longitude) && distanceMeters(point,candidate)<=2000))throw Error('location_not_saved');
}

export function distanceMeters(a, b) {
  const radians = value => value * Math.PI / 180;
  const dlat = radians(b.latitude - a.latitude), dlon = radians(b.longitude - a.longitude);
  const h = Math.sin(dlat / 2) ** 2 + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(dlon / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}
