export const STORES = {
  carrefour: {name:'Carrefour',hosts:['www.carrefour.ke','carrefour.ke'],home:'https://www.carrefour.ke/mafken/en',cart:'https://www.carrefour.ke/mafken/en/app/cart'},
  quickmart: {name:'Quickmart',hosts:['www.quickmart.co.ke','quickmart.co.ke'],home:'https://www.quickmart.co.ke/',cart:'https://www.quickmart.co.ke/'},
  naivas: {name:'Naivas',hosts:['www.naivas.online','naivas.online'],home:'https://www.naivas.online/',cart:'https://www.naivas.online/cart/index'}
};
export const APP_ORIGINS = ['https://deal-agent-beta.onrender.com','http://localhost:4000'];
export function appOrigin(url) { try { return APP_ORIGINS.includes(new URL(url).origin); } catch { return false; } }
export function storeURL(value,store) {
  try { const u=new URL(value);return u.protocol==='https:' && STORES[store]?.hosts.includes(u.hostname) && !u.username && !u.password && !u.port; } catch {return false;}
}
export function validatePlan(plan, now=Date.now()) {
  if(!plan || typeof plan!=='object' || JSON.stringify(plan).length>65536)throw Error('Basket is too large.');
  if(!plan || plan.version!==1 || !STORES[plan.store] || !/^[A-Za-z0-9_-]{16,64}$/.test(plan.request_id || '') ||
    !Number.isInteger(plan.created_at) || plan.created_at*1000>now+60000 || now-plan.created_at*1000>1800000 ||
    !Array.isArray(plan.products) || !plan.products.length || plan.products.length>50) throw Error('Invalid or expired basket. Send a fresh basket from Shopping Agent.');
  const ids=new Set();
  const products=plan.products.map(p=>{
    if(!p || typeof p.id!=='string' || !/^[A-Za-z0-9_-]{1,64}$/.test(p.id) || ids.has(p.id) ||
      typeof p.name!=='string' || !p.name.trim() || p.name.length>300 || typeof p.query!=='string' || p.query.length>200 ||
      !Number.isInteger(p.packs) || p.packs<1 || p.packs>50 || typeof p.expected_price!=='string' || !/^\d{1,8}(?:\.\d{1,2})?$/.test(p.expected_price) ||
      !storeURL(p.url,plan.store)) throw Error('Invalid product in basket.');
    const u=new URL(p.url);
    if(u.search || u.hash || (plan.store==='carrefour' ? !u.pathname.endsWith('/p/'+p.id) : /^\/(cart|checkout|customer|users|shops|login|register)(\/|$)/.test(u.pathname) || u.pathname==='/')) throw Error('Invalid product link.');
    ids.add(p.id);
    return {id:p.id,name:p.name,url:u.href,query:p.query,packs:p.packs,expected_price:p.expected_price};
  });
  const delivery={};
  if(typeof plan.delivery?.label==='string')delivery.label=plan.delivery.label.slice(0,200);
  if(typeof plan.delivery?.branch_id==='string' && /^\d{1,10}$/.test(plan.delivery.branch_id))delivery.branch_id=plan.delivery.branch_id;
  return {version:1,request_id:plan.request_id,created_at:plan.created_at,store:plan.store,products,delivery};
}
export const permissionsFor=store=>STORES[store].hosts.map(host=>`https://${host}/*`);
export function itemURL(job) {
  const p=job.plan.products[job.index];
  if(job.plan.store==='quickmart')return `https://www.quickmart.co.ke/shops/products/${job.branch}/keyword-${encodeURIComponent(p.query)}`;
  if(job.plan.store==='naivas')return 'https://www.naivas.online/search?term='+encodeURIComponent(p.query);
  return p.url;
}
