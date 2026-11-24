// Chrome native messaging: no listening network port, shared cookies or tokens.
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
for(const key of ['OPENAI_API_KEY','ANTHROPIC_API_KEY','OPENROUTER_API_KEY'])delete process.env[key];
const {firefox}=await import('../carrefour_browser/node_modules/playwright/index.mjs');
const {validatePlan}=await import('../../extension/policy.js');
const {createLocalCart}=await import('./cart.mjs');
const {messageDecoder,encodeMessage}=await import('./protocol.mjs');
let cart,requestId,starting=false,expiry,deadline;
const emit=event=>process.stdout.write(encodeMessage({request_id:requestId,...event}));
const close=async()=>{clearTimeout(expiry);clearTimeout(deadline);await cart?.close().catch(()=>{});process.exit(0);};
process.on('SIGTERM',close);process.stdin.on('end',close);
process.stdout.on('error',close);
const receive=async message=>{
  if(message?.action==='prepare') {
    if(cart || starting)throw Error('already_running');
    const plan=validatePlan(message.plan);
    if(plan.store!=='carrefour')throw Error('unsupported_store');
    requestId=plan.request_id;starting=true;
    expiry=setTimeout(close,1800000);
    deadline=setTimeout(async()=>{emit({status:'attention',message:'Cart preparation timed out. Stop this attempt before preparing another cart.'});await close();},240000);
    cart=await createLocalCart({plan,launch:headless=>firefox.launch({headless,timeout:30000}),emit});
    await cart.prepare();clearTimeout(deadline);starting=false;
  } else {
    if(message?.action==='close' && message.request_id===requestId)return close();
    if(!cart || message?.request_id!==requestId || starting)throw Error('session_busy');
    if(message.action==='open')await cart.open();
    else if(message.action==='close')await close();
    else throw Error('invalid_command');
  }
};
const decode=messageDecoder(message=>receive(message).catch(()=>emit({status:'attention',message:'The local helper could not complete this operation. Stop this attempt and check the helper installation before trying again.'})));
process.stdin.on('data',chunk=>{try{decode(chunk);}catch{close();}});
