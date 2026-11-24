if(!globalThis.__shoppingAgentBridgeInstalled) {
  globalThis.__shoppingAgentBridgeInstalled=true;
  const checkoutVersion=chrome.runtime.getManifest().version;
  chrome.runtime.onMessage.addListener((message,sender)=>{
    if(sender.id!==chrome.runtime.id || message.type!=='job:progress')return;
    window.postMessage({source:'shopping-agent-extension',type:'basket:progress',version:checkoutVersion,request_id:message.request_id,store:message.store,status:message.status,message:message.message},location.origin);
  });
// Only basket descriptions cross this bridge. Never read store cookies or login fields.
window.addEventListener('message', async event => {
  if(event.source!==window || event.origin!==location.origin || event.data?.source!=='shopping-agent' || !['basket:offer','basket:control','helper:offer','helper:control'].includes(event.data.type))return;
  const offer=event.data.type.endsWith(':offer');
  const helper=event.data.type.startsWith('helper:');
  const request=offer?event.data.plan?.request_id:event.data.request_id;
  try {
    if(JSON.stringify(event.data).length>65536)return;
    const result=await chrome.runtime.sendMessage(offer?{type:helper?'helper:import':'basket:import',plan:event.data.plan}:{type:helper?'helper:control':'basket:control',request_id:request,action:event.data.action});
    window.postMessage({source:'shopping-agent-extension',version:checkoutVersion,request_id:request,control:!offer,...result,error:result.error ? `${result.error} (checkout ${result.version || checkoutVersion}; ${result.validator || 'unknown validator'})` : undefined},location.origin);
  }catch {
    window.postMessage({source:'shopping-agent-extension',version:checkoutVersion,request_id:request,error:'Reload Shopping Agent after installing or updating the extension.'},location.origin);
  }
});

}
