import {STORES,APP_ORIGINS,appOrigin,storeURL,validatePlan,itemURL} from './policy.js';
import {cartStep} from './adapters.js';
let queue=Promise.resolve();
const exclusive=fn=>{const next=queue.then(fn);queue=next.catch(()=>{});return next;};
const inFlight=new Set();
const read=async()=> (await chrome.storage.session.get('job')).job;
const write=async job=>chrome.storage.session.set({job});
const internal=sender=>sender.id===chrome.runtime.id && sender.url?.startsWith(chrome.runtime.getURL(''));
const ui=()=>chrome.tabs.create({url:chrome.runtime.getURL('checkout.html')});
const operationProduct=job=>job.plan.products[job.index];
const destination=job=>{
  if(['clear','verify','finalverify'].includes(job.phase))return job.plan.store==='quickmart'?`https://www.quickmart.co.ke/shops/products/${job.branch}/keyword-${encodeURIComponent(operationProduct(job).query)}`:STORES[job.plan.store].cart;
  return itemURL(job);
};

const checkRequest=(job,request)=>{if(request && job?.plan.request_id!==request)throw Error('This order has been replaced. Prepare the current order again.');};
async function startBackground(request) {
  await exclusive(async()=>{
    const job=await read();checkRequest(job,request);
    if(!job)throw Error('Send an order from Shopping Agent first.');
    validatePlan(job.plan);
    if(job.tabId)return;
    if(!await chrome.permissions.contains({origins:STORES[job.plan.store].hosts.map(host=>`https://${host}/*`)})) {
      await write({...job,status:'permission_required',message:`Enable ${STORES[job.plan.store].name} access once to prepare your cart in the background.`});return;
    }
    // Start blank so browser tooling can attach before the retailer navigation.
    // active:false keeps the shopper on the comparison page throughout preparation.
    const tab=await chrome.tabs.create({url:'about:blank',active:false});
    const next={...job,tabId:tab.id,index:0,phase:'probe',status:'opening',message:'Connecting to your supermarket in the background…'};
    await write(next);
    try {
      await chrome.tabs.update(tab.id,{url:STORES[job.plan.store].home});
      await write({...next,status:'loading',expectedURL:STORES[job.plan.store].home});
    }catch(error){await write({...next,status:'attention',message:'Could not open the supermarket. Prepare this order again.'});}
  });
  drive().catch(()=>{});
}
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
    const j=await read();if(!j || j.flow!=='fresh-cart-v1' || j.status!=='loading' || inFlight.has(j.plan.request_id))return null;
    try{validatePlan(j.plan);}catch{return null;}
    const tab=await chrome.tabs.get(j.tabId).catch(()=>null);
    if(!tab || tab.status!=='complete')return null;
    if(!storeURL(tab.url,j.plan.store) || (j.phase!=='probe' && new URL(tab.url).pathname.replace(/\/$/,'')!==new URL(j.expectedURL).pathname.replace(/\/$/,'')) || (j.phase==='probe' && /\/(?:login|signin|sign-in|register)(?:\/|$)/i.test(new URL(tab.url).pathname))) {
      await write({...j,status:'attention',message:'The store needs your attention. Open the supermarket to sign in or confirm delivery, then resume here.'});return null;
    }
    inFlight.add(j.plan.request_id);
    await write({...j,status:'executing',message:`Checking ${j.phase==='probe'?'your store session':j.phase==='clear'?'the old cart':j.phase==='finalverify'?'your completed cart':operationProduct(j).name}…`});
    return j;
  });
  if(!job)return;
  try {
    const product=operationProduct(job);
    const result=await runStep(job.tabId,{
      store:job.plan.store,product,products:job.phase==='finalverify'?job.plan.products:[product],
      phase:['verify','finalverify'].includes(job.phase)?'verify':job.phase,
      branch:job.branch,readonly:job.phase==='finalverify',exact:job.phase==='finalverify'
    });
    if(!result.ok)throw Error('The store did not confirm this cart step.');
    const next=await exclusive(async()=>{
      const latest=await read();if(latest?.plan.request_id!==job.plan.request_id || latest.status!=='executing')return null;
      if(job.phase==='finalverify') {
        await write({...job,status:'ready',message:'Fresh cart verified: only this order’s selected products and quantities are in the supermarket cart. Review delivery fees and the final total on the store website before paying.'});
        return null;
      }
      if(job.phase==='probe') {
        if(job.plan.delivery.branch_id && result.branch!==job.plan.delivery.branch_id)throw Error('Your Quickmart branch differs from the compared branch. Open the store and select the same branch, or compare again.');
        return {...job,branch:result.branch,started:true,index:0,phase:'preflight'};
      }
      if(job.phase==='clear')return {...job,index:0,phase:'items'};
      if(job.phase==='items')return {...job,phase:'verify'};
      const index=job.index+1;
      if(job.phase==='preflight')return {...job,index:index<job.plan.products.length?index:0,phase:index<job.plan.products.length?'preflight':'clear'};
      return {...job,index:index<job.plan.products.length?index:0,phase:index<job.plan.products.length?'items':'finalverify'};
    });
    if(next)await go(next,destination(next));
  }catch(error){await attention(job.plan.request_id,error.message?.includes('Frame with ID')?'The store navigated during a step. Inspect the basket before resuming.':String(error.message || 'Store step interrupted. Review before resuming.'));}
  finally{inFlight.delete(job.plan.request_id);drive().catch(()=>{});}
}
async function receive(message,sender) {
  if(message.type==='basket:import') {
    if(!sender.tab || !appOrigin(sender.url))throw Error('Basket source is not allowed.');
    const plan=validatePlan(message.plan);
    await exclusive(async()=>{
      const old=await read();
      if(old?.plan.request_id===plan.request_id)return;
      // A new explicit order supersedes the previous transfer, including failed jobs.
      // Close a running helper before accepting new instructions so it cannot keep clicking.
      if(old?.tabId && (['opening','probing','executing','loading'].includes(old.status) || inFlight.has(old.plan.request_id)))await chrome.tabs.remove(old.tabId).catch(()=>{});
      await write({plan,flow:'fresh-cart-v1',appTabId:sender.tab.id,status:'starting',index:0,phase:'probe',message:'Preparing your fresh cart in the background…'});
    });
    await startBackground(plan.request_id);const current=await read();return {accepted:true,background:true,status:current?.status,message:current?.message};
  }
  if(message.type==='basket:control') {
    const job=await read();
    if(!sender.tab || !appOrigin(sender.url) || job?.appTabId!==sender.tab.id)throw Error('Order control source is not allowed.');
    checkRequest(job,message.request_id);
    const actions={focus:'job:focus',resume:'job:resume',stop:'job:clear',setup:'job:setup'};
    if(!Object.hasOwn(actions,message.action) || !message.request_id)throw Error('Unknown order action.');
    message={type:actions[message.action],request_id:message.request_id};
  } else if(!internal(sender))throw Error('Extension control source is not allowed.');
  if(message.type==='job:get')return {job:await read()};
  if(message.type==='job:setup'){checkRequest(await read(),message.request_id);await ui();return {ok:true};}
  if(message.type==='job:clear') {
    const old=await exclusive(async()=>{
      const j=await read();checkRequest(j,message.request_id);
      if(j)await write({...j,status:'stopped',message:'Cart preparation stopped. You can prepare a new order from this page.'});
      await chrome.storage.session.remove('job');return j;
    });
    if(old?.tabId && (['opening','probing','executing','loading'].includes(old.status) || inFlight.has(old.plan.request_id)))await chrome.tabs.remove(old.tabId).catch(()=>{});
    return {ok:true};
  }
  if(message.type==='job:open') {
    checkRequest(await read(),message.request_id);
    await startBackground(message.request_id);
    const job=await read();
    // Permission setup is the only normal checkout action outside the app.
    if(job?.appTabId)await chrome.tabs.update(job.appTabId,{active:true}).catch(()=>{});
    return {ok:true};
  }
  if(message.type==='job:resume') {
    const job=await exclusive(async()=>{
      const j=await read();checkRequest(j,message.request_id);if(!j?.tabId || !['awaiting_user','attention'].includes(j.status))throw Error('Open the supermarket and confirm delivery first.');
      validatePlan(j.plan);
      if(j.flow!=='fresh-cart-v1')throw Error('Send a new order from Shopping Agent after updating the extension.');
      inFlight.add(j.plan.request_id);
      await write({...j,status:'probing',message:'Checking the selected store…'});return j;
    });
    try {
      const tab=await chrome.tabs.get(job.tabId);
      if(tab.status!=='complete')throw Error('Wait for the supermarket page to finish loading, then resume.');
      if(!storeURL(tab.url,job.plan.store))throw Error('Finish signing in, then return to the supermarket in its original tab.');
      const result=await runStep(job.tabId,{store:job.plan.store,phase:'probe'});
      if(job.plan.delivery.branch_id && result.branch!==job.plan.delivery.branch_id)throw Error('Your Quickmart branch differs from the compared branch. Select the same branch or compare prices again.');
      let next={...job,branch:result.branch};
      if(job.branch && job.branch!==result.branch)throw Error('The branch changed during this transfer. Return to the previous branch or stop the transfer.');
      if(!job.started || job.phase==='probe')next={...next,started:true,index:0,phase:'preflight'};
      await go(next,destination(next));
      return {ok:true};
    }catch(error){await attention(job.plan.request_id,error.message);throw error;}
    finally{inFlight.delete(job.plan.request_id);drive().catch(()=>{});}
  }
  if(message.type==='job:focus') {
    const job=await read();checkRequest(job,message.request_id);if(job?.tabId)await chrome.tabs.update(job.tabId,{active:true});return {ok:true};
  }
  throw Error('Unknown extension action.');
}
chrome.runtime.onMessage.addListener((message,sender,reply)=>{
  const respond=result=>reply({...result,version:chrome.runtime.getManifest().version,validator:'offer-links-v2'});
  receive(message,sender).then(respond,error=>respond({error:String(error.message || 'Checkout extension error').slice(0,500)}));return true;
});
chrome.storage.onChanged.addListener((changes,area)=>{
  const job=changes.job?.newValue;
  if(area!=='session' || !job?.appTabId || job.plan.version<2)return;
  chrome.tabs.get(job.appTabId).then(tab=>{
    if(appOrigin(tab.url))return chrome.tabs.sendMessage(tab.id,{type:'job:progress',request_id:job.plan.request_id,store:job.plan.store,status:job.status,message:job.message});
  }).catch(()=>{});
});
chrome.tabs.onUpdated.addListener((_id,change)=>{if(change.status==='complete')drive().catch(()=>{});});
chrome.tabs.onRemoved.addListener(tabId=>{exclusive(async()=>{const job=await read();if(job?.tabId===tabId)await write({...job,tabId:null,status:'closed',message:'The supermarket tab closed. Click Prepare cart to start this order again.'});}).catch(()=>{});});
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
  exclusive(async()=>{
    const old=await read();
    if(old && old.flow!=='fresh-cart-v1') {
      if(old.tabId && ['opening','probing','executing','loading'].includes(old.status))await chrome.tabs.remove(old.tabId).catch(()=>{});
      await chrome.storage.session.remove('job');
    }
  }).catch(()=>{});
  // Fresh-cart mode no longer needs persistent product receipts from 0.1.3.
  chrome.storage.local.get(null).then(data=>chrome.storage.local.remove(Object.keys(data).filter(key=>key.startsWith('cart-history:')))).catch(()=>{});
  chrome.tabs.query({url:APP_ORIGINS.map(origin=>origin+'/*')}).then(tabs=>Promise.all(tabs.map(tab=>
    chrome.scripting.executeScript({target:{tabId:tab.id},files:['bridge.js']}).catch(()=>{})
  ))).catch(()=>{});
});
