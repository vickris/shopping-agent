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
  if(current.label!==selected[0].StoreName.trim())throw Error('location_not_saved');
  step('retaining_location');
  await navigate('https://foodplus.co.ke/catalogsearch/result/?q=milk');
  const retained=await readLocation(page,'foodplus');
  if(JSON.stringify(retained)!==JSON.stringify(current))throw Error('location_not_saved');
  return {...retained,confirmation:'geolocation'};
}
