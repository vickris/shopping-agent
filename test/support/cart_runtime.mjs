import readline from 'node:readline';
const input = readline.createInterface({input:process.stdin});
let started = false, paused = false;
const emit = event => console.log(JSON.stringify(event));
input.on('line', line => {
  const message = JSON.parse(line);
  if (!started) {
    started = true;
    if (message.store === 'quickmart') {
      paused = true;
      emit({status:'awaiting_input',verified:false,message:'Enter your Quickmart delivery location, then continue.'});
    } else emit({status:'ready', verified:true, message:'Your Carrefour cart is filled and verified. Review it and pay in the Carrefour browser window.'});
  } else if (message.action === 'resume' && paused) {
    paused=false;
    emit({status:'needs_attention',verified:true,message:'Your Quickmart cart is filled and verified.'});
  } else if (message.action === 'close') process.exit(0);
});
input.on('close',()=>process.exit(0));
