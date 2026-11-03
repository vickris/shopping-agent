import {readLocation} from './delivery_location.mjs';

// Let Foodplus's native geolocation flow choose and save the branch. The
// read-only lookup verifies that its displayed branch is the GPS resolver's
// selected branch, rather than the default "Main Website Store" catalogue.
export async function selectFoodplusLocation(page, point, navigate, step) {
  step('saving_location');
  const useLocation=page.locator('#store-popup [data-role="use-location"]:visible');
  if(await useLocation.count())await useLocation.click();
  await page.waitForFunction(()=>{
    const label=document.querySelector('#switcher-store-trigger strong span')?.textContent.trim();
    return label && !/Main Website Store|Select Store/i.test(label) &&
      !document.querySelector('.store-selection-modal._show');
  },null,{timeout:30000});
  step('verifying_location');
  let data=await page.evaluate(async point=>{
    const query=new URLSearchParams({lattitude:String(point.latitude),longitude:String(point.longitude)});
    const response=await fetch('/rest/default/V1/geoswitcher/storeswitcher/?'+query,{signal:AbortSignal.timeout(15000)});
    if(!response.ok)throw Error('location_unconfirmed');
    return await response.json();
  },point);
  if(typeof data==='string')data=JSON.parse(data);
  const selected=data.success && data.availableStores?.filter(store=>store.storeCode!=='admin' && Number(store.isSelected)===1);
  if(!selected || selected.length!==1)throw Error('location_unconfirmed');
  const current=await readLocation(page,'foodplus');
  // Foodplus abbreviates a selected branch in its header: for example, the
  // resolver's "Adlife Plaza Kilimani" is rendered as "Adlife Plaza". Accept
  // only a complete, meaningful leading label, never a loose substring, so a
  // different branch cannot be mistaken for the GPS-selected one.
  if(!sameBranch(current.label,selected[0].StoreName))throw Error('location_not_saved');
  step('retaining_location');
  await navigate('https://foodplus.co.ke/catalogsearch/result/?q=milk');
  const retained=await readLocation(page,'foodplus');
  if(JSON.stringify(retained)!==JSON.stringify(current))throw Error('location_not_saved');
  return {...retained,confirmation:'geolocation'};
}

export function sameBranch(current, selected) {
  const words=value=>String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g,' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  const displayed=words(current), resolved=words(selected);
  return displayed.length >= 2 &&
    displayed.length <= resolved.length &&
    displayed.every((word,index)=>word===resolved[index]);
}
