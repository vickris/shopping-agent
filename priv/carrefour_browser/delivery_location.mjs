// Only visible store UI is used; no account data or cookies leave the browser.
const roots = {carrefour: 'www.carrefour.ke', quickmart: 'www.quickmart.co.ke', naivas: 'www.naivas.online'};
export async function readLocation(page, store, {ignoreDialog = false} = {}) {
  const host = new URL(page.url()).hostname.replace(/^www\./, '');
  if (host !== roots[store]?.replace(/^www\./, '')) throw Error('location_unconfirmed');
  const dialog = store === 'quickmart' ? '#frmModalPopupUserLocation:visible' : store === 'naivas' ? '#address_drawer[role="dialog"][aria-hidden="false"]:visible' : '[role="dialog"]:visible';
  if (!ignoreDialog && await page.locator(dialog).count()) throw Error('location_dialog_open');
  let label, branch_id, branch;
  if (store === 'carrefour') {
    label = (await page.locator('header button').filter({has: page.locator('img[src*="Caret_Down_Arrow_for_address_location"]')}).innerText({timeout: 3000})).trim();
  } else if (store === 'naivas') {
    label = (await page.locator('.geoLocation:visible').first().innerText({timeout: 3000})).trim();
  } else {
    label = (await page.locator('.js-location-address:visible').first().innerText({timeout: 3000})).trim();
    const report = page.locator('a[href*="/shops/report-spam/"]').first();
    if (!await report.count()) throw Error('branch_not_open');
    branch_id = (await report.getAttribute('href'))?.match(/\/shops\/report-spam\/(\d+)/)?.[1];
    if (!branch_id) throw Error('branch_not_open');
    const heading = page.locator('h6:visible').first();
    branch = await heading.count() ? (await heading.innerText()).trim() : undefined;
  }
  if (!label || /enter your|select (address|location)/i.test(label)) throw Error('location_unconfirmed');
  return {label, ...(branch_id ? {branch_id, ...(branch ? {branch} : {})} : {})};
}

export async function confirmLocation(page, store, area, initial, navigate) {
  if (store === 'quickmart' && !await page.locator('a[href*="/shops/report-spam/"]').count()) {
    // Saving an address can redirect to /home. Follow the selected branch in
    // the navigation rather than expecting users to open its page themselves.
    const href = await page.locator('a.navigation-link:visible').evaluateAll(links =>
      links.map(link => link.getAttribute('href')).find(href => /^\/\d+\/?$/.test(href || '')));
    if (!href) throw Error('branch_not_open');
    await navigate(new URL(href, page.url()).href);
  }
  const selected = await readLocation(page, store, {ignoreDialog: store === 'naivas'});
  if (store !== 'naivas' && initial && JSON.stringify(selected) === JSON.stringify(initial) && !selected.label.toLowerCase().includes(area.toLowerCase())) throw Error('location_not_saved');
  if (store === 'naivas') {
    // Naivas may leave its address drawer open after choosing an address.
    // The user explicitly allows Naivas to keep its original map location.
    const close = page.locator('#address_drawer[role="dialog"][aria-hidden="false"] #close-address-drawer');
    if (await close.count()) {
      await close.click();
      await page.locator('#address_drawer[role="dialog"][aria-hidden="false"]').waitFor({state: 'hidden', timeout: 3000});
    }
  }
  const location = await readLocation(page, store);
  return store === 'naivas' ? {...location, confirmation: 'user_override'} : location;
}

export function confirmationError(store, error) {
  if (error.message === 'branch_not_open') return 'Quickmart has not selected a branch yet. Choose a delivery address and press Continue in Quickmart, then try again.';
  if (error.message === 'location_not_saved') return 'The store still reports its original delivery location. Save or select your address in the store first, then try again.';
  if (error.message === 'location_dialog_open') return 'Finish and close the store’s delivery-location dialog, then try again.';
  return (store === 'naivas' ? 'Naivas' : store === 'quickmart' ? 'Quickmart' : 'Carrefour') + ' has not exposed a selected delivery location yet. Finish saving the address in its window, then try again.';
}
