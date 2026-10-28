import {confirmLocation} from './delivery_location.mjs';

// Use the supermarket's own visible location workflow and map provider. Never
// select a default branch when automatic resolution fails.
export async function selectAutomaticLocation(page, store, point, navigate) {
  if (store === 'naivas') {
    // Naivas's map exception is explicit in the app; native geolocation is
    // supplied to its browser, but delivery coverage is not claimed as verified.
    return confirmLocation(page, store, 'Near you', undefined, navigate);
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
    const input = page.locator('#pac-input-add-address.pac-target-input:visible');
    await input.waitFor({state: 'visible', timeout: 20000});
    // Carrefour exposes address search rather than a GPS button. Resolve an
    // address with its already-loaded Google Maps SDK, then use that search UI.
    const address = await page.evaluate(async point => {
      const {results} = await Promise.race([
        new google.maps.Geocoder().geocode({location: {lat: point.latitude, lng: point.longitude}}),
        new Promise((_, reject) => setTimeout(() => reject(Error('map_timeout')), 10000))
      ]);
      const named = results.filter(r => !r.formatted_address.includes('+'));
      const result = named.find(r => r.types.some(type => ['street_address', 'premise'].includes(type))) || named.find(r => r.types.includes('sublocality')) || named.find(r => r.types.includes('route'));
      return result?.formatted_address;
    }, point);
    if (!address) throw Error('location_unconfirmed');
    await input.fill(address);
    const predictions = page.locator('.pac-item:visible');
    await predictions.first().waitFor({state: 'visible', timeout: 10000});
    const addresses = await predictions.evaluateAll(els => els.slice(0, 5).map(el => Array.from(el.childNodes).map(node => node.textContent.trim()).filter(Boolean).join(' ')));
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
    if (!nearest || nearest.distance > 2000) throw Error('location_unconfirmed');
    const selectedPrediction = predictions.nth(nearest.index);
    const currentAddress = await selectedPrediction.evaluate(el => Array.from(el.childNodes).map(node => node.textContent.trim()).filter(Boolean).join(' '));
    if (currentAddress !== addresses[nearest.index]) throw Error('location_unconfirmed');
    await selectedPrediction.click({timeout: 10000});
    const deliver = page.getByRole('button', {name: 'Yes, deliver to this location', exact: true});
    await deliver.waitFor({state: 'visible', timeout: 15000});
    // The cookie banner can mount after the address dialog opens. Its controls
    // can be aria-hidden by that dialog while still intercepting real clicks.
    await page.getByRole('button', {name: 'Accept All Cookies', exact: true, includeHidden: true}).click({timeout: 3000}).catch(() => {});
    await deliver.click({timeout: 15000});
    await page.getByRole('dialog', {name: /Confirm delivery location|Add delivery location/i}).waitFor({state: 'hidden', timeout: 15000});
  }
  const location = await confirmLocation(page, store, 'Near you', undefined, navigate);
  return {...location, confirmation: 'geolocation'};
}

export function distanceMeters(a, b) {
  const radians = value => value * Math.PI / 180;
  const dlat = radians(b.latitude - a.latitude), dlon = radians(b.longitude - a.longitude);
  const h = Math.sin(dlat / 2) ** 2 + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(dlon / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}
