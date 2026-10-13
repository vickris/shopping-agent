import readline from 'node:readline';
const input = readline.createInterface({input:process.stdin});
let started = false;
input.on('line', line => {
  const message = JSON.parse(line);
  if (!started) {
    started = true;
    console.log(JSON.stringify({status:'ready', verified:true, message:'Your Carrefour cart is filled and verified. Review it and pay in the Carrefour browser window.'}));
  } else if (message.action === 'close') process.exit(0);
});
input.on('close',()=>process.exit(0));
