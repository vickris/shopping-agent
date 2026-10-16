// One temporary, in-memory browser context per shopper/store. No cookie export.
import readline from 'node:readline';
import {fileURLToPath} from 'node:url';
import {realpathSync} from 'node:fs';
import {fillCart} from './cart_flow.mjs';
import {readLocation, confirmLocation, confirmationError} from './delivery_location.mjs';
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
delete process.env.OPENAI_API_KEY;
delete process.env.ANTHROPIC_API_KEY;
export async function runSession({input,emit,onSetup,onError,headless=false}) {
const setup = await new Promise(resolve=>input.once('line',line=>resolve(JSON.parse(line))));
const roots={carrefour:'https://www.carrefour.ke/mafken/en',quickmart:'https://www.quickmart.co.ke/',naivas:'https://www.naivas.online/'};
let browser,page,confirmed,initialIdentity,busy=false,resume;
const cents = value => {
  const match=String(value).replaceAll(',','').match(/^(\d+)(?:\.(\d{1,2}))?$/);
  if(!match)throw Error('invalid_price');
  return BigInt(match[1])*100n+BigInt((match[2]||'').padEnd(2,'0'));
};
async function navigate(url) {
  const response=await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
  if(!response?.ok())throw Error('store_unavailable');
}
const identity = (ignoreDialog = false) => readLocation(page, setup.store, {ignoreDialog});
async function assertLocation() {
  if(!confirmed)throw Error('location_unconfirmed');
  for(let i=0;i<6;i++) {
    try {
      const current=await identity();
      if(JSON.stringify(current)===JSON.stringify(confirmed))return;
    } catch {}
    await page.waitForTimeout(250);
  }
  throw Error('location_changed');
}

async function pause(message) {
  emit({type:'cart',status:'awaiting_input',message,verified:false});
  await page.bringToFront();
  await new Promise(resolve=>{resume=resolve;});
  await assertLocation();
}
input.on('line',async line=>{
  let message;
  try {message=JSON.parse(line);}catch{return;}
  if(message.action==='close'){await browser?.close();process.exit(0);}
  if(message.action==='open'){await page?.bringToFront();return;}
  if(message.action==='resume' && resume){const next=resume;resume=null;next();return;}
  if(busy){emit({type:'reply',id:message.id,error:'session_busy'});return;}
  busy=true;
  try {
    if(message.action==='confirm') {
      const selected=await confirmLocation(page,setup.store,setup.area,initialIdentity,navigate);
      const {confirmation,...identity}=selected;
      confirmed=identity;
      emit({type:'confirmed',location:{area:setup.area,...confirmed,...(confirmation?{confirmation}: {})}});
    } else if(message.action==='search') {
      // A moved/expired location never falls back to the default area.
      await assertLocation();
      const url=setup.store==='quickmart'
        ? 'https://www.quickmart.co.ke/shops/products/'+confirmed.branch_id+'/keyword-'+encodeURIComponent(message.query)
        : roots[setup.store]+(setup.store==='naivas'?'search?term=':'/search?keyword=')+encodeURIComponent(message.query);
      await navigate(url);
      await assertLocation();
      await page.locator(setup.store==='quickmart'
        ? '#products-listing .productInfoJs, #frmProductSearchPaging input[name="recordDisplayCount"][value="0"]'
        : setup.store==='naivas' ? 'div.border-naivas-bg a span.line-clamp-2, h2:has-text("0 Search Results Found")'
        : 'div.group a[href*="/p/"] span.line-clamp-2, img[src*="no-result-found.svg"]').first().waitFor({state:'attached',timeout:15000});
      await assertLocation();
      emit({type:'reply',id:message.id,html:await page.content()});
    } else if(message.action==='cart') {
      if(message.plan.store!==setup.store || !Array.isArray(message.plan.products) || !message.plan.products.length)throw Error('invalid_basket');
      const domain=new URL(roots[setup.store]).hostname;
      for (const p of message.plan.products) {
        const url=new URL(p.url);
        if(url.protocol!=='https:' || ![domain,domain.replace(/^www\./,'')].includes(url.hostname) || url.username || url.password || url.port || !/^\d+$/.test(p.id) || !Number.isInteger(p.packs) || p.packs<1 || p.packs>50)throw Error('invalid_basket');
        cents(p.expected_price);
      }
      await assertLocation();
      const checkedNavigate=async url=>{await navigate(url);await assertLocation();};
      emit({type:'cart',status:'preparing',message:setup.store==='naivas'?'Preparing your Naivas basket. Delivery to your supplied area must be checked in Naivas checkout.':'Preparing your basket at the confirmed delivery location.'});
      const result=await fillCart({page,plan:{...message.plan,delivery:confirmed},navigate:checkedNavigate,cents,pause,
        emit:event=>emit({type:'cart',...event})});
      await assertLocation();
      emit({type:'cart',...result});
      await page.bringToFront();
    }
  } catch(error) {
    const kind=['location_changed','location_unconfirmed','session_busy','invalid_basket','price_changed','cart_mismatch'].includes(error.message)?error.message:'store_unavailable';
    if(message.action==='confirm')emit({type:'confirmation_failed',message:confirmationError(setup.store,error)});
    else if(message.action==='cart')emit({type:'cart',status:'failed',verified:false,message:'Cart preparation stopped ('+kind+'). Review the store window; no automatic retry was made.'});
    else emit({type:'reply',id:message.id,error:kind});
    if(message.action!=='confirm' && (kind==='location_changed'||kind==='location_unconfirmed')){confirmed=null;emit({type:'invalidated'});}
  } finally {busy=false;}
});
input.on('close',async()=>{await browser?.close();process.exit(0);});
try {
  if(!roots[setup.store] || typeof setup.area!=='string' || setup.area.length>200)throw Error('invalid_setup');
  const {firefox,chromium}=await import('playwright');
  browser=await (setup.store==='quickmart'?chromium:firefox).launch({headless,...(setup.store==='quickmart'?{channel:'chromium'}:{})});
  browser.on('disconnected',()=>{emit({type:'closed'});process.exit(0);});
  page=await (await browser.newContext()).newPage();
  await navigate(setup.store==='carrefour' ? roots.carrefour+'/search?keyword=milk' : setup.store==='quickmart' ? roots.quickmart+'shops/products/1/keyword-milk' : roots.naivas+'search?term=milk');
  try { initialIdentity=await identity(true); } catch {}
  if(onSetup)await onSetup(page);
  emit({type:'setup',status:'awaiting_input',message:setup.store==='naivas'?'You can try selecting the address in Naivas. If its map does not update, choose Use this area for Naivas in the app to proceed with delivery unverified.':'Select your delivery area in this store window. For Quickmart press Continue after choosing the address; the selected branch will open automatically when you confirm. Confirm here only when the store accepts delivery to your area.'});
  await page.bringToFront();
} catch(error) {if(onError)await onError(error);emit({type:'setup_error',message:error.name==='TimeoutError'?'The store took too long to load. Retry delivery setup.':'The store browser could not open. Check the installed browser runtime and connection, then retry.'});emit({type:'closed'});await browser?.close();process.exit(1);}

}
if (process.argv[1] && realpathSync(process.argv[1])===fileURLToPath(import.meta.url)) {
  await runSession({input:readline.createInterface({input:process.stdin}),
    emit:event=>process.stdout.write(JSON.stringify(event)+'\n'),headless:process.argv.includes('--test')});
}
