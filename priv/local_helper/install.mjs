import {mkdir,writeFile} from 'node:fs/promises';
import {homedir,platform} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
const [extensionId,browser='chrome']=process.argv.slice(2);
if(!/^[a-p]{32}$/.test(extensionId || '') || !['chrome','edge'].includes(browser)) {
  throw Error('Usage: node priv/local_helper/install.mjs EXTENSION_ID [chrome|edge]');
}
const os=platform();
if(!['darwin','linux'].includes(os))throw Error('This installer currently supports macOS and Linux.');
const root=join(homedir(),'.local','share','deal-agent');
await mkdir(root,{recursive:true,mode:0o700});
const launcher=join(root,'cart-helper');
const quote=value=>"'"+value.replaceAll("'","'\\''")+"'";
await writeFile(launcher,`#!/bin/sh\nexec ${quote(process.execPath)} ${quote(fileURLToPath(new URL('./host.mjs',import.meta.url)))} "$@"\n`,{mode:0o700});
const directory=os==='darwin'
  ?join(homedir(),'Library','Application Support',browser==='chrome'?'Google/Chrome':'Microsoft Edge','NativeMessagingHosts')
  :join(homedir(),'.config',browser==='chrome'?'google-chrome':'microsoft-edge','NativeMessagingHosts');
await mkdir(directory,{recursive:true});
const path=join(directory,'io.deal_agent.cart_helper.json');
await writeFile(path,JSON.stringify({name:'io.deal_agent.cart_helper',description:'Local headless Carrefour cart helper',path:launcher,type:'stdio',allowed_origins:[`chrome-extension://${extensionId}/`]},null,2)+'\n',{mode:0o600});
console.log(`Registered local Carrefour helper for ${browser}: ${path}\nReload the checkout extension, then prepare a Carrefour cart. Keep this project at its current path.`);
