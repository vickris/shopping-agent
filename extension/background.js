import {STORES,APP_ORIGINS,appOrigin,storeURL,validatePlan,itemURL} from './policy.js';
import {cartStep} from './adapters.js';
let queue=Promise.resolve();
const exclusive=fn=>{const next=queue.then(fn);queue=next.catch(()=>{});return next;};
const inFlight=new Set();
const read=async()=> (await chrome.storage.session.get('job')).job;
const write=async job=>chrome.storage.session.set({job});
const internal=sender=>sender.id===chrome.runtime.id && sender.url?.startsWith(chrome.runtime.getURL(''));
const ui=()=>chrome.tabs.create({url:chrome.runtime.getURL('checkout.html')});
async function runStep(tabId,args) {
  let result;
  try {result=(await chrome.scripting.executeScript({target:{tabId},func:cartStep,args:[args]}))[0]?.result;}
  catch {throw Error('The store tab changed or access was removed. Finish signing in on the supermarket website, then review the cart before resuming.');}
  if(!result || result.error)throw Error(result?.error || 'The store page is not ready. Confirm its location and try again.');
  return result;
}
async function attention(id,message) {
  await exclusive(async()=>{const job=await read();if(job?.plan.request_id===id)await write({...job,status:'attention',message:message.slice(0,500)});});
}
async function go(job,url) {
  const current=await exclusive(async()=>{
    const latest=await read();
    if(latest?.plan.request_id!==job.plan.request_id || latest.status==='cancelled')return false;
    await write({...job,status:'loading',expectedURL:url});return true;
  });
  if(current) {
    try{await chrome.tabs.update(job.tabId,{url});}
    catch{await attention(job.plan.request_id,'The supermarket tab closed. Send a fresh basket.');}
  }
}
async function drive() {
  const job=await exclusive(async()=>{
    const j=await read();if(!j || j.status!=='loading' || inFlight.has(j.plan.request_id))return null;
    try{validatePlan(j.plan);}catch{return null;}
    const tab=await chrome.tabs.get(j.tabId).catch(()=>null);
    if(!tab || tab.status!=='complete')return null;
    if(!storeURL(tab.url,j.plan.store) || new URL(tab.url).pathname!==new URL(j.expectedURL).pathname) {
      await write({...j,status:'attention',message:'The store redirected. Sign in or confirm delivery in the store tab, then return here and resume.'});return null;
    }
    inFlight.add(j.plan.request_id);
    await write({...j,status:'executing',message:`Checking ${j.phase==='items'?j.plan.products[j.index].name:'your basket'}…`});
    return j;
  });
  if(!job)return;
  try {
    const result=await runStep(job.tabId,{
      store:job.plan.store,product:job.plan.products[job.index],products:job.plan.products,phase:job.phase,branch:job.branch
    });
    if(!result.ok)throw Error('The store did not confirm this cart step.');
    const next=await exclusive(async()=>{
      const latest=await read();if(latest?.plan.request_id!==job.plan.request_id || latest.status!=='executing')return null;
      if(job.phase==='verify') {
        await write({...job,status:'ready',message:'Selected products and quantities checked. Review every basket item, delivery fee and final total on the store website before paying.'});
        return null;
      }
      const index=job.index+1;
      return {...job,index:index<job.plan.products.length?index:0,phase:index<job.plan.products.length?'items':'verify'};
    });
    if(next)await go(next,next.phase==='items'?itemURL(next):next.plan.store==='quickmart'?`https://www.quickmart.co.ke/shops/products/${next.branch}/keyword-${encodeURIComponent(next.plan.products[0].query)}`:STORES[next.plan.store].cart);
  }catch(error){await attention(job.plan.request_id,error.message?.includes('Frame with ID')?'The store navigated during a step. Inspect the basket before resuming.':String(error.message || 'Store step interrupted. Review before resuming.'));}
  finally{inFlight.delete(job.plan.request_id);drive().catch(()=>{});}
}
async function receive(message,sender) {
  if(message.type==='basket:import') {
    if(!sender.tab || !appOrigin(sender.url))throw Error('Basket source is not allowed.');
    const plan=validatePlan(message.plan);
    await exclusive(async()=>{
      const old=await read();
      if(old && Date.now()-old.plan.created_at*1000<1800000) {
        if(old.plan.request_id===plan.request_id)return;
        throw Error('Finish or clear the previous basket in the extension first.');
      }
      if(old?.tabId && ['executing','loading'].includes(old.status))await chrome.tabs.remove(old.tabId).catch(()=>{});
      await write({plan,status:'review',index:0,phase:'items',message:'Review the basket below before opening the supermarket.'});
    });
    await ui();return {accepted:true};
  }
  if(!internal(sender))throw Error('Extension control source is not allowed.');
  if(message.type==='job:get')return {job:await read()};
  if(message.type==='job:clear') {
    const old=await exclusive(async()=>{const j=await read();await chrome.storage.session.remove('job');return j;});
    if(old?.tabId && ['executing','loading'].includes(old.status))await chrome.tabs.remove(old.tabId).catch(()=>{});
    return {ok:true};
  }
  if(message.type==='job:open') {
    return exclusive(async()=>{
      const job=await read();if(!job)throw Error('Send a basket from Shopping Agent first.');
      validatePlan(job.plan);
      if(job.tabId){await chrome.tabs.update(job.tabId,{active:true});return {ok:true};}
      // Permission must already have been approved by a click in the extension page.
      const origins=STORES[job.plan.store].hosts.map(host=>`https://${host}/*`);
      if(!await chrome.permissions.contains({origins}))throw Error('Allow access to this supermarket first.');
      const tab=await chrome.tabs.create({url:STORES[job.plan.store].home});
      await write({...job,tabId:tab.id,status:'awaiting_user',message:'Sign in normally and set the delivery location in the supermarket tab. Then return here and build the basket.'});
      return {ok:true};
    });
  }
  if(message.type==='job:resume') {
    const job=await exclusive(async()=>{
      const j=await read();if(!j?.tabId || !['awaiting_user','attention'].includes(j.status))throw Error('Open the supermarket and confirm delivery first.');
      validatePlan(j.plan);
      inFlight.add(j.plan.request_id);
      await write({...j,status:'probing',message:'Checking the selected store…'});return j;
    });
    try {
      const tab=await chrome.tabs.get(job.tabId);
      if(tab.status!=='complete')throw Error('Wait for the supermarket page to finish loading, then resume.');
      if(!storeURL(tab.url,job.plan.store))throw Error('Finish signing in, then return to the supermarket in its original tab.');
      const result=await runStep(job.tabId,{store:job.plan.store,phase:'probe'});
      if(job.plan.delivery.branch_id && result.branch!==job.plan.delivery.branch_id)throw Error('Your Quickmart branch differs from the compared branch. Select the same branch or compare prices again.');
      const next={...job,index:0,phase:'items',branch:result.branch};
      await go(next,itemURL(next));
      return {ok:true};
    }catch(error){await attention(job.plan.request_id,error.message);throw error;}
    finally{inFlight.delete(job.plan.request_id);drive().catch(()=>{});}
  }
  if(message.type==='job:focus') {
    const job=await read();if(job?.tabId)await chrome.tabs.update(job.tabId,{active:true});return {ok:true};
  }
  throw Error('Unknown extension action.');
}
chrome.runtime.onMessage.addListener((message,sender,reply)=>{
  receive(message,sender).then(reply,error=>reply({error:String(error.message || 'Checkout extension error').slice(0,500)}));return true;
});
chrome.tabs.onUpdated.addListener((_id,change)=>{if(change.status==='complete')drive().catch(()=>{});});
chrome.tabs.onRemoved.addListener(tabId=>{exclusive(async()=>{const job=await read();if(job?.tabId===tabId)await write({...job,tabId:null,status:'attention',message:'The supermarket tab closed. Clear this transfer and send a new basket; your store cart remains in your browser account.'});}).catch(()=>{});});
chrome.action.onClicked.addListener(()=>ui());
chrome.alarms.create('expire-basket',{periodInMinutes:1});
chrome.alarms.onAlarm.addListener(()=>{
  exclusive(async()=>{
    const job=await read();if(!job)return;
    if(Date.now()-job.plan.created_at*1000>1800000) {
      await chrome.storage.session.remove('job');
      if(job.tabId && ['loading','executing'].includes(job.status))await chrome.tabs.remove(job.tabId).catch(()=>{});
    }else if(['executing','probing'].includes(job.status) && !inFlight.has(job.plan.request_id)) {
      await write({...job,status:'attention',message:'The browser interrupted a cart step. Inspect the basket before explicitly resuming.'});
    }
  }).catch(()=>{});
});

// Attach to already-open Shopping Agent tabs on install/update without losing
// the shopper's current list to a page reload. No retailer scripts run here.
chrome.runtime.onInstalled.addListener(()=>{
  chrome.tabs.query({url:APP_ORIGINS.map(origin=>origin+'/*')}).then(tabs=>Promise.all(tabs.map(tab=>
    chrome.scripting.executeScript({target:{tabId:tab.id},files:['bridge.js']}).catch(()=>{})
  ))).catch(()=>{});
});
