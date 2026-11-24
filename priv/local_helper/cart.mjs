import {cartStep} from '../../extension/adapters.js';
import {openBrowserSession} from '../carrefour_browser/browser_handoff.mjs';

// Navigation retries are GET-only. Never retry an uncertain add-to-cart action.
export async function navigateCartPage(page,url) {
  for(let attempt=0;attempt<2;attempt++) {
    try {
      const response=await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
      if(!response?.ok())throw Error('store_unavailable');
      return;
    } catch(error) {
      if(attempt || !/NS_ERROR_NET_HTTP[23]_PROTOCOL_ERROR|ERR_HTTP2_PROTOCOL_ERROR/.test(error.message))throw error;
    }
  }
}

// The session stays on this computer. Only bounded progress messages leave it.
export async function createLocalCart({plan,launch,emit}) {
  let browser=await launch(true),page,opened=false,busy=false,closed=false,verified=false;
  const disconnected=()=>{closed=true;emit({status:'closed',message:'The Carrefour browser was closed.'});};
  browser.on('disconnected',disconnected);
  try {
    const context=await browser.newContext();
    page=await context.newPage();
  } catch(error) {await browser.close();throw error;}
  const navigate=url=>navigateCartPage(page,url);
  const step=async(candidate,phase,product)=>{
    const result=await candidate.evaluate(cartStep,{store:'carrefour',phase,product,products:plan.products,readonly:phase==='verify',exact:phase==='verify'});
    if(!result?.ok)throw Object.assign(Error('store_prompt'),{userMessage:result?.error?.slice(0,500)});
  };
  return {
    async prepare() {
      busy=true;
      try {
        emit({status:'loading',message:`Adding ${plan.products[0].name} to Carrefour…`});
        await navigate('https://www.carrefour.ke/mafken/en/app/cart');
        await step(page,'probe');
        await step(page,'clear');
        for(const product of plan.products) {
          emit({status:'executing',message:`Adding ${product.name} to Carrefour…`});
          await navigate(product.url);
          await step(page,'items',product);
        }
        await navigate('https://www.carrefour.ke/mafken/en/app/cart');
        await step(page,'verify');
        verified=true;
        emit({status:'ready',message:'Your Carrefour cart is ready. Review it and checkout.'});
      } catch(error) {
        emit({status:'attention',message:error.userMessage || 'Carrefour could not load the cart. Open Carrefour to check the connection or delivery requirements, then stop this attempt before trying again.'});
      } finally {busy=false;}
    },
    async open() {
      if(busy || closed)throw Error('session_busy');
      busy=true;
      try {
        if(opened){await page.bringToFront();return;}
        const next=await openBrowserSession({page,launch:()=>launch(false),origin:'https://www.carrefour.ke',
          verify:async candidate=>{if(verified)await step(candidate,'verify');}});
        const previous=browser;
        previous.off('disconnected',disconnected);
        browser=next.browser;page=next.page;opened=true;
        browser.on('disconnected',disconnected);
        await previous.close();
        emit({status:verified?'ready':'attention',message:'Carrefour is open on this computer. Review your address and cart, then complete checkout yourself.'});
      } catch {
        emit({status:verified?'ready':'attention',message:'The Carrefour window could not restore and verify this cart. The original session is retained; try opening it again.'});
      } finally {busy=false;}
    },
    async close(){closed=true;await browser.close();}
  };
}
