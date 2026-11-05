import {lookup} from 'node:dns/promises';
import {BlockList, isIP} from 'node:net';
const blocked = new BlockList();
for (const [ip, prefix] of [['0.0.0.0',8],['10.0.0.0',8],['100.64.0.0',10],['127.0.0.0',8],['169.254.0.0',16],['172.16.0.0',12],['192.0.0.0',24],['192.168.0.0',16],['198.18.0.0',15],['224.0.0.0',4],['240.0.0.0',4]]) blocked.addSubnet(ip,prefix);
const globalIPv6 = new BlockList();
globalIPv6.addSubnet('2000::',3,'ipv6');
export function publicAddress(ip) {
  return isIP(ip) === 4 ? !blocked.check(ip) : isIP(ip) === 6 && globalIPv6.check(ip,'ipv6') && !ip.toLowerCase().startsWith('2001:db8:');
}
export async function publicURL(value, resolve = lookup) {
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || (url.port && url.port !== '443')) return false;
    const host = url.hostname.replace(/^\[|\]$/g,'');
    if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local') || host.endsWith('.internal')) return false;
    const addresses = isIP(host) ? [{address:host}] : await resolve(host,{all:true});
    return addresses.length > 0 && addresses.every(({address}) => publicAddress(address));
  } catch { return false; }
}
export async function restrictNetwork(context) {
  await context.route('**/*', async route => {
    if (await publicURL(route.request().url())) await route.continue();
    else await route.abort('blockedbyclient');
  });
  // Do not expose a server-side websocket route to private endpoints either.
  await context.routeWebSocket('**/*', async ws => {
    const url = ws.url().replace(/^wss:/,'https:');
    if (await publicURL(url)) ws.connectToServer(); else ws.close();
  });
}
