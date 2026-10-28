import readline from 'node:readline';
const input=readline.createInterface({input:process.stdin});
const emit=event=>console.log(JSON.stringify(event));
let setup, confirmations=0;
input.on('line',line=>{
 const m=JSON.parse(line);
 if(!setup){setup=m;if(m.coordinates){if(m.area==='Automatic retry'){emit({type:'setup',status:'unavailable',message:'Store location could not be confirmed automatically.'});return;}emit({type:'confirmed',location:{area:m.area,label:'Nearby service area',confirmation:'geolocation',...(m.store==='quickmart'?{branch_id:'73',branch:'Nearby Quickmart'}:{})}});return;}emit({type:'setup',status:'awaiting_input',message:'Select the store delivery location, then confirm.'});return;}
 if(m.action==='locate')setTimeout(()=>emit({type:'confirmed',location:{area:setup.area,label:'Nearby service area',confirmation:'geolocation'}}),100);
 if(m.action==='open'){emit({type:'window',status:'opening'});setTimeout(()=>emit(setup.area==='Window failure'?{type:'window',status:'failed',message:'The original basket is retained.'}:{type:'window',status:'opened'}),100);}
 if(m.action==='close')process.exit(0);
 if(m.action==='confirm' && setup.area==='Retry' && confirmations++===0){setTimeout(()=>emit({type:'confirmation_failed',message:'Save the store delivery address, then try again.'}),100);return;}
 if(m.action==='confirm')emit({type:'confirmed',location:{area:setup.area,label:setup.area+', Kenya',...(setup.store==='naivas'?{confirmation:'user_override'}:{}),...(setup.store==='quickmart'?{branch_id:'7701'}:{})}});
 if(m.action==='search'){
  const reply=()=>emit(m.query==='changed'?{type:'reply',id:m.id,error:'location_changed'}:{type:'reply',id:m.id,html:`<div class="group"><a href="/mafken/en/milk/p/247170"><span class="line-clamp-2">Milk 500ml</span></a><div class="items-baseline"><span>KES</span><span>65.00</span></div><span class="line-clamp-1">500ml</span><button aria-label="Add to cart"></button></div>`});
  if(m.query==='slow')setTimeout(reply,200);else reply();
  if(m.query==='changed')emit({type:'invalidated'});
 }
 if(m.action==='cart')emit({type:'cart',status:'needs_attention',verified:true,message:'Cart filled at the confirmed delivery location.'});
});
input.on('close',()=>process.exit(0));
