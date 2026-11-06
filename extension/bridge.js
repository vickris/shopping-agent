if(!globalThis.__shoppingAgentBridgeInstalled) {
  globalThis.__shoppingAgentBridgeInstalled=true;
  const checkoutVersion=chrome.runtime.getManifest().version;
// Only basket descriptions cross this bridge. Never read store cookies or login fields.
window.addEventListener('message', async event => {
  if(event.source!==window || event.origin!==location.origin || event.data?.source!=='shopping-agent' || event.data.type!=='basket:offer')return;
  const request=event.data.plan?.request_id;
  try {
    if(JSON.stringify(event.data.plan || {}).length>65536)return;
    const result=await chrome.runtime.sendMessage({type:'basket:import',plan:event.data.plan});
    window.postMessage({source:'shopping-agent-extension',version:checkoutVersion,request_id:request,...result},location.origin);
  }catch {
    window.postMessage({source:'shopping-agent-extension',version:checkoutVersion,request_id:request,error:'Reload Shopping Agent after installing or updating the extension.'},location.origin);
  }
});

}
