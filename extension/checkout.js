import {STORES,permissionsFor} from './policy.js';
const $=id=>document.getElementById(id);
let job;
async function send(type) {
  const result=await chrome.runtime.sendMessage({type});
  if(result.error)throw Error(result.error);return result;
}
async function refresh() {
  const result=await send('job:get');job=result.job;
  $('basket').hidden=!job;$('empty').hidden=Boolean(job);
  if(!job){$('status').textContent='No active basket transfer.';return;}
  $('heading').textContent=`${STORES[job.plan.store].name} checkout`;
  $('status').textContent=job.message;
  $('branch').textContent=job.plan.delivery.label?`Compared store location: ${job.plan.delivery.label}. Confirm your delivery address on the supermarket website.`:'Confirm your delivery address on the supermarket website.';
  $('products').replaceChildren(...job.plan.products.map(p=>{
    const li=document.createElement('li');
    const name=document.createElement('strong');name.textContent=p.name;
    const detail=document.createElement('span');detail.textContent=`${p.packs} pack(s) · KES ${p.expected_price} per pack`;
    li.append(name,detail);return li;
  }));
  $('open').disabled=Boolean(job.tabId);
  $('resume').disabled=!job.tabId || !['awaiting_user','attention'].includes(job.status);
  $('focus').disabled=!job.tabId;
}
function action(id,fn) {$(id).addEventListener('click',async()=>{try{$(id).disabled=true;await fn();await refresh();}catch(e){$('status').textContent=e.message;$(id).disabled=false;}});}
action('open',async()=>{
  if(!job)return;
  const allowed=await chrome.permissions.request({origins:permissionsFor(job.plan.store)});
  if(!allowed)throw Error('Supermarket access was not granted. No basket changes were made.');
  await send('job:open');
});
action('resume',()=>send('job:resume'));
action('focus',()=>send('job:focus'));
action('clear',()=>send('job:clear'));
chrome.storage.onChanged.addListener((_changes,area)=>{if(area==='session')refresh().catch(()=>{});});
refresh().catch(error=>{$('status').textContent=error.message;});
