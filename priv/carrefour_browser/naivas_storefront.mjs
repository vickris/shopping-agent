export const naivasLocationSelector='button[data-slot="dropdown-menu-trigger"]:has(span.truncate)';
export const naivasSearchURL=query=>'https://www.naivas.online/search?q='+encodeURIComponent(query.trim());
export async function modernNaivas(page) {
  return await page.locator(naivasLocationSelector).count()>0;
}
export async function waitForNaivasSearch(page) {
  await page.waitForFunction(()=>{
    const main=document.querySelector('main');
    const text=main?.textContent || '';
    const count=text.match(/([\d,]+)\s+Result\(s\)/)?.[1];
    if(count==='0')return true;
    if(count && main.querySelector('div.group p.line-clamp-2'))return true;
    return Boolean(document.querySelector('div.border-naivas-bg a span.line-clamp-2')) || [...document.querySelectorAll('h2')].some(el=>/^\s*0 Search Results Found\s*$/.test(el.textContent));
  },null,{timeout:25000});
}
export async function readModernNaivasLocation(page) {
  const trigger=page.locator(naivasLocationSelector).filter({visible:true}).first();
  await trigger.waitFor({state:'visible',timeout:10000});
  await page.waitForFunction(selector=>[...document.querySelectorAll(selector)].some(el=>{
    const label=el.textContent.trim();return el.getClientRects().length && label && !/^Nairobi,?\s*Kenya$|select.*address|your address/i.test(label);
  }),naivasLocationSelector,{timeout:10000});
  return {label:(await trigger.innerText()).trim()};
}
export async function selectModernNaivasLocation(page,point,navigate,step) {
  step('opening_location');
  const selectAddress=page.getByRole('button',{name:'Select Address',exact:true});
  // Server-rendered controls can precede React hydration. Retry only opening
  // the menu, and only after verifying that the first click had no effect.
  for(let attempt=0;attempt<3 && !await selectAddress.isVisible();attempt++) {
    const trigger=page.locator(naivasLocationSelector).filter({visible:true}).first();
    if(await trigger.getAttribute('aria-expanded')!=='true')await trigger.click();
    await selectAddress.waitFor({state:'visible',timeout:5000}).catch(()=>{});
  }
  await selectAddress.click();
  const dialog=page.getByRole('dialog').filter({hasText:'Select your delivery address'});
  await dialog.waitFor({state:'visible',timeout:15000});
  step('loading_map');
  await dialog.getByRole('button',{name:'Locate Me',exact:true}).click();
  step('reverse_geocoding');
  await page.waitForFunction(()=>{
    const dialog=[...document.querySelectorAll('[role="dialog"]')].find(el=>el.textContent.includes('Select your delivery address'));
    const address=dialog && [...dialog.querySelectorAll('button')].find(el=>el.querySelector('div.truncate'));
    return address && address.textContent.trim() && !/your address\.*/i.test(address.textContent);
  },null,{timeout:25000});
  step('saving_location');
  await dialog.getByRole('button',{name:'Confirm Location',exact:true}).click();
  await dialog.waitFor({state:'hidden',timeout:25000});
  const details=page.getByRole('dialog').filter({hasText:'Delivery Address'});
  if(await details.isVisible())throw Error('address_details_required');
  step('verifying_location');
  const selected=await readModernNaivasLocation(page);
  step('retaining_location');
  await navigate(naivasSearchURL('milk'));
  const retained=await readModernNaivasLocation(page);
  if(retained.label!==selected.label)throw Error('location_not_saved');
  return {...retained,confirmation:'geolocation'};
}
