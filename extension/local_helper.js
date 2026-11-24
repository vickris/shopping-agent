import {appOrigin,validatePlan} from './policy.js';
export const HELPER_HOST='io.deal_agent.cart_helper';

export function localHelper(chrome) {
  let port,job;
  const publish=async(status,message)=>{
    if(!job)return;
    const next={...job,status,message};
    job=next;
    await chrome.storage.session.set({helperJob:next});
    await chrome.tabs.sendMessage(next.appTabId,{type:'job:progress',request_id:next.plan.request_id,store:'carrefour',status,message}).catch(()=>{});
  };
  const disconnect=()=>{
    if(port){const previous=port;port=null;previous.disconnect();}
    job=null;
  };
  chrome.tabs.onRemoved?.addListener(tabId=>{if(job?.appTabId===tabId)disconnect();});
  chrome.tabs.onUpdated?.addListener((tabId,change)=>{if(job?.appTabId===tabId && change.status==='loading')disconnect();});
  return async(message,sender)=>{
    if(!sender.tab || !appOrigin(sender.url))throw Error('Helper source is not allowed.');
    if(message.type==='helper:import') {
      const plan=validatePlan(message.plan);
      if(plan.store!=='carrefour')throw Error('The local helper currently supports Carrefour only.');
      if(job && port)throw Error('Stop the existing Carrefour helper cart before preparing another.');
      job={plan,appTabId:sender.tab.id,status:'starting'};
      port=chrome.runtime.connectNative(HELPER_HOST);
      const current=port;
      current.onMessage.addListener(event=>{
        if(port!==current || event.request_id!==job?.plan.request_id)return;
        if(!['loading','executing','ready','attention','closed'].includes(event.status) || typeof event.message!=='string')return;
        publish(event.status,event.message.slice(0,500)).catch(()=>{});
        if(event.status==='closed'){port=null;current.disconnect();}
      });
      current.onDisconnect.addListener(()=>{
        void chrome.runtime.lastError;
        if(port!==current)return;
        port=null;
        publish('closed','Local helper disconnected. Install or restart the helper, then prepare your cart again.').catch(()=>{});
      });
      await publish('starting','Adding your selected items…');
      current.postMessage({action:'prepare',plan});
      return {accepted:Boolean(port),status:job.status,message:job.message,error:port?undefined:'Local helper unavailable. Install the helper and reload the extension before trying again.'};
    }
    if(message.type!=='helper:control' || !job || sender.tab.id!==job.appTabId || message.request_id!==job.plan.request_id)throw Error('Helper order control is not allowed.');
    if(message.action==='stop') {
      if(port){port.postMessage({action:'close',request_id:job.plan.request_id});const previous=port;port=null;previous.disconnect();}
      await publish('stopped','Local cart preparation stopped. You can prepare a fresh cart.');
      job=null;return {ok:true};
    }
    if(message.action!=='focus' || !port || !['ready','attention'].includes(job.status))throw Error('Wait for preparation to finish before opening Carrefour.');
    port.postMessage({action:'open',request_id:job.plan.request_id});
    return {ok:true};
  };
}
