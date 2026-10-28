import {randomUUID} from 'node:crypto';
// Guest state stays inside this process. Never write it to disk or send it to Phoenix.
export async function openBrowserSession({page, launch, contextOptions={}, origin, verify}) {
  const context=page.context();
  const storageState=await context.storageState({indexedDB:true});
  const sessionStorage=await page.evaluate(()=>Object.fromEntries(Object.entries(window.sessionStorage)));
  const sessionOrigin=new URL(page.url()).origin;
  let nextBrowser;
  try {
    nextBrowser=await launch();
    const nextContext=await nextBrowser.newContext({...contextOptions,storageState});
    if(contextOptions.geolocation)await nextContext.grantPermissions(['geolocation'],{origin});
    await nextContext.addInitScript(({origin,entries,marker})=>{
      if(window.location.origin===origin && !window.sessionStorage.getItem(marker)) {
        window.sessionStorage.setItem(marker,'1');
        for(const [key,value] of Object.entries(entries))window.sessionStorage.setItem(key,value);
      }
    },{origin:sessionOrigin,entries:sessionStorage,marker:'__deal_agent_handoff_'+randomUUID()});
    const nextPage=await nextContext.newPage();
    const response=await nextPage.goto(page.url(),{waitUntil:'domcontentloaded',timeout:30000});
    if(!response?.ok())throw Error('store_unavailable');
    await verify(nextPage);
    await nextPage.bringToFront();
    return {browser:nextBrowser,page:nextPage};
  } catch(error) {
    await nextBrowser?.close().catch(()=>{});
    // The original browser remains alive; retrying never adds products again.
    throw error;
  }
}
