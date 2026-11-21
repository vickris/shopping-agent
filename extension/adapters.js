// Self-contained: Chrome serializes this function into an ISOLATED world.
// Only visible cart controls are used. Never click sign-in, checkout or payment.
export async function cartStep({store,product,products,phase,branch,receipt,readonly=false,minimumQuantity}) {
  const issue=message=>Object.assign(new Error(message),{expected:true});
  const visible=el=>Boolean(el && el.getClientRects().length && getComputedStyle(el).visibility!=='hidden');
  const all=(selector,root=document)=>Array.from(root.querySelectorAll(selector));
  const text=el=>(el?.textContent || '').trim();
  const wait=async(fn,ms=20000)=>{const end=Date.now()+ms;while(Date.now()<end){const v=fn();if(v)return v;await new Promise(r=>setTimeout(r,200));}throw issue('Store controls did not settle. Review the store tab before resuming.');};
  const cents=value=>{const clean=String(value).replace(/KES|KSh|\s|,/gi,'');const m=clean.match(/^(\d+)(?:\.(\d{1,2}))?$/);if(!m)throw issue('Could not read a selling price.');return BigInt(m[1])*100n+BigInt((m[2]||'').padEnd(2,'0'));};
  const click=el=>{if(!visible(el) || el.disabled)throw issue('Required store control is unavailable.');el.click();};
  const priceText=el=>{if(!el)throw issue('Selling price is unavailable.');const copy=el.cloneNode(true);copy.querySelectorAll('del,s,.line-through').forEach(n=>n.remove());return text(copy);};
  const expected=p=>cents(p.expected_price);
  const checkPrice=(value,p)=>{if(cents(value)!==expected(p))throw issue('The store price changed for '+p.name+'. Compare prices again before continuing.');};
  const path=value=>new URL(value,location.href).pathname;
  // No operation may execute on Google, payment pages or a redirected product.
  const hosts={carrefour:['www.carrefour.ke','carrefour.ke'],quickmart:['www.quickmart.co.ke','quickmart.co.ke'],naivas:['www.naivas.online','naivas.online']};
  if(location.protocol!=='https:' || !hosts[store]?.includes(location.hostname))return {error:'Return to the supermarket tab after signing in.'};
  if(globalThis.__shoppingAgentCartBusy)return {error:'A store step is still running. Wait before resuming.'};
  globalThis.__shoppingAgentCartBusy=true;
  try {
    if(phase==='probe') {
      if(store==='quickmart') {
        const address=all('.js-location-address').find(visible);
        if(!text(address) || /enter your delivery address/i.test(text(address)))throw issue('Set your delivery address on Quickmart first.');
        const links=all('a[href]');
        const id=links.map(a=>a.getAttribute('href').match(/\/shops\/report-spam\/(\d+)/)?.[1]).find(Boolean) || links.filter(a=>a.matches('.navigation-link')).map(a=>a.getAttribute('href').match(/^\/(\d+)\/?$/)?.[1]).find(Boolean);
        if(!id)throw issue('Choose and open your Quickmart branch first.');
        return {branch:id};
      }
      if(store==='naivas') {
        const location=all('.geoLocation').find(visible);
        if(!text(location))throw issue('Set your delivery address on Naivas first.');
      }
      return {ok:true};
    }
    // Read before adding: existing quantities belong to the shopper, not this order.
    if(phase==='inspect' || phase==='cleanup') {
      let quantity, decrease;
      if(store==='carrefour') {
        if(!location.pathname.endsWith('/p/'+product.id))throw issue('The previous product redirected. Review its cart entry manually.');
        const panel=await wait(()=>all('main > div.relative.grid').find(el=>el.querySelector('h1')));
        const controls=await wait(()=>all('div.flex.flex-col.gap-sm',panel).find(el=>text(el).includes('Get It Delivered By')));
        await wait(()=>all('[role="combobox"],button',controls).some(el=>visible(el) && (el.getAttribute('role')==='combobox'||text(el)==='Add to cart')));
        await new Promise(r=>setTimeout(r,1000));
        quantity=()=>{const counter=all('[role="combobox"]',controls).find(visible);return counter?Number(text(counter)):all('button',controls).some(el=>visible(el)&&text(el)==='Add to cart')?0:NaN;};
        decrease=()=>click(controls.querySelector('svg[data-testid="minus-icon"],svg[data-testid="delete-icon"],svg[data-testid="trash-icon"]')?.closest('button'));
      } else if(store==='quickmart') {
        if(!location.pathname.startsWith('/shops/products/'+branch+'/'))throw issue('The Quickmart branch changed.');
        const card=await wait(()=>all('#products-listing .productInfoJs').find(el=>all('input.qty-input',el).some(input=>input.dataset.key===product.id)));
        if(path(card.querySelector('a.products-title')?.href)!==path(product.url))throw issue('Quickmart returned a different product.');
        await new Promise(r=>setTimeout(r,500));
        quantity=()=>visible(card.querySelector('.quantityBlockJs'))?Number(card.querySelector('input.qty-input').value):visible(card.querySelector('button[name="btnAddToCart"]'))?0:NaN;
        decrease=()=>click(card.querySelector('.decrease-js'));
      } else if(phase==='inspect') {
        const card=await wait(()=>all('div.border-naivas-bg').filter(el=>all('input[name="product_id"]',el).some(input=>input.value===product.id)).sort((a,b)=>a.querySelectorAll('*').length-b.querySelectorAll('*').length)[0]);
        if(!all('a[href]',card).some(a=>path(a.href)===path(product.url)))throw issue('Naivas returned a different product.');
        await new Promise(r=>setTimeout(r,750));
        quantity=()=>{const counter=all('button',card).find(el=>visible(el)&&/^\d+$/.test(text(el)));return counter?Number(text(counter)):all('form button',card).some(el=>visible(el)&&/ADD TO CART/i.test(text(el)))?0:NaN;};
      } else {
        const rows=()=>all('div.rounded-xl.p-4.w-full').filter(el=>el.querySelector('span[x-text="quantity"]'));
        await wait(()=>rows().length || /cart is empty|basket is empty/i.test(text(document.querySelector('main') || document.body)));
        const row=()=>rows().find(el=>all('a[wire\\:click]',el).some(a=>a.getAttribute('wire:click')===`redirectToProductPage(${product.id})`));
        quantity=()=>row()?Number(text(row().querySelector('span[x-text="quantity"]'))):0;
        decrease=()=>click(all('a[wire\\:click]',row()).find(a=>a.getAttribute('wire:click')===`updateQuantity(${product.id}, 'decrement')`));
      }
      const initial=quantity();
      if(!Number.isInteger(initial)||initial<0)throw issue('Could not read the previous cart quantity.');
      if(phase==='inspect')return {ok:true,quantity:initial};
      // Already checked out / manually removed, or a previously completed cleanup.
      if(initial===0 || initial===receipt.before)return {ok:true};
      if(initial!==receipt.after)throw issue('The quantity changed for '+product.name+'. Review it manually; only previous Shopping Agent quantities can be removed.');
      for(let n=initial;n>receipt.before;n--) {
        decrease();
        await wait(()=>quantity()===n-1);
      }
      if(quantity()!==receipt.before)throw issue('The previous Shopping Agent item could not be removed. Review the store cart.');
      return {ok:true};
    }
    if(phase==='items' && store==='carrefour') {
      if(!location.pathname.endsWith('/p/'+product.id))throw issue('The product redirected to a different page.');
      const panel=await wait(()=>all('main > div.relative.grid').find(el=>el.querySelector('h1')));
      await wait(()=>all('[role="combobox"],button',panel).find(el=>visible(el)&&(el.getAttribute('role')==='combobox'||text(el)==='Add to cart')));
      await new Promise(r=>setTimeout(r,1000));
      checkPrice(priceText(panel.querySelector('.force-ltr')),product);
      const controls=all('div.flex.flex-col.gap-sm',panel).find(el=>text(el).includes('Get It Delivered By'));
      if(!controls)throw issue('Delivery controls are unavailable. Confirm your address on Carrefour.');
      const counter=()=>all('[role="combobox"]',controls).find(visible);
      if(!counter()) {click(all('button',controls).find(el=>text(el)==='Add to cart'));await wait(()=>counter() && Number(text(counter()))>=1);}
      for(let n=0;n<50;n++) {
        const qty=Number(text(counter()));if(!Number.isInteger(qty)||qty<1)throw issue('Could not read the cart quantity.');
        if(qty===product.packs)return {ok:true};
        const plus=qty<product.packs;
        const icon=controls.querySelector(`svg[data-testid="${plus?'plus':'minus'}-icon"]`);
        click(icon?.closest('button'));
        await wait(()=>Number(text(counter()))===qty+(plus?1:-1));
      }
      throw issue('Quantity limit reached.');
    }
    if(phase==='items' && store==='quickmart') {
      if(!location.pathname.startsWith('/shops/products/'+branch+'/'))throw issue('The Quickmart branch changed.');
      const card=await wait(()=>all('#products-listing .productInfoJs').find(el=>all('input.qty-input',el).some(input=>input.dataset.key===product.id)));
      if(path(card.querySelector('a.products-title')?.href)!==path(product.url))throw issue('Quickmart returned a different product.');
      checkPrice(text(card.querySelector('.products-price-new')),product);
      const quantity=card.querySelector('input.qty-input');
      await new Promise(r=>setTimeout(r,500));
      if(!visible(card.querySelector('.quantityBlockJs'))) {
        click(card.querySelector('button[name="btnAddToCart"]'));
        await wait(()=>visible(card.querySelector('.quantityBlockJs')) && Number(quantity.value)>=1);
      }
      for(let n=0;n<50;n++) {
        const qty=Number(quantity.value);if(!Number.isInteger(qty)||qty<1)throw issue('Could not read the cart quantity.');
        if(qty===product.packs)return {ok:true};
        const plus=qty<product.packs;click(card.querySelector(plus?'.increase-js':'.decrease-js'));
        await wait(()=>Number(quantity.value)===qty+(plus?1:-1));
      }
      throw issue('Quantity limit reached.');
    }
    if(phase==='items' && store==='naivas') {
      const card=await wait(()=>all('div.border-naivas-bg').filter(el=>all('input[name="product_id"]',el).some(input=>input.value===product.id)).sort((a,b)=>a.querySelectorAll('*').length-b.querySelectorAll('*').length)[0]);
      if(!all('a[href]',card).some(a=>path(a.href)===path(product.url)))throw issue('Naivas returned a different product.');
      checkPrice(text(card.querySelector('.product-price span.font-bold')),product);
      await new Promise(r=>setTimeout(r,750));
      const counter=()=>all('button',card).find(el=>visible(el)&&/^\d+$/.test(text(el)));
      if(!counter()) {
        click(all('form button',card).find(el=>visible(el)&&/ADD TO CART/i.test(text(el))));
        await wait(()=>counter());
      }
      return {ok:true};
    }
    if(phase==='verify' && store==='quickmart') {
      click(all('button.button-cart').find(visible));
      await wait(()=>visible(document.querySelector('#sideCartJs')));
      await wait(()=>products.every(p=>all('#sideCartJs li.list-cart-item').some(el=>all('a.product-profile-title',el).some(a=>path(a.href)===path(p.url)) && text(el.querySelector('.selected-quantity'))===`Quantity: ${p.packs}`)));
      const rows=all('#sideCartJs li.list-cart-item');
      for(const p of products) {
        const row=rows.find(el=>all('a.product-profile-title',el).some(a=>path(a.href)===path(p.url)));
        if(!row || text(row.querySelector('.selected-quantity'))!==`Quantity: ${p.packs}`)throw issue('Quickmart cart quantity does not match your selection.');
        checkPrice(text(row.querySelector('.products-price-new')),p);
      }
      return {ok:true,extras:Math.max(0,rows.length-products.length)};
    }
    if(phase==='verify' && store==='naivas') {
      for(const p of products) {
        const row=await wait(()=>all('div.rounded-xl.p-4.w-full').find(el=>all('a[wire\\:click]',el).some(a=>a.getAttribute('wire:click')===`redirectToProductPage(${p.id})`)));
        const counter=()=>row.querySelector('span[x-text="quantity"]');
        await wait(()=>/^\d+$/.test(text(counter())));
        for(let n=0;n<50;n++) {
          const qty=Number(text(counter()));if(!Number.isInteger(qty)||qty<1)throw issue('Could not read the cart quantity.');
          if(cents(text(row.querySelector('.font-extrabold')))!==expected(p)*BigInt(qty))throw issue('Naivas changed a selected price. Review it before continuing.');
          if(qty===p.packs)break;
          if(readonly || (minimumQuantity!==undefined && (qty<minimumQuantity || qty>p.packs)))throw issue('Naivas cart quantity changed outside this transfer. Review it before continuing.');
          const plus=qty<p.packs;
          click(all('a[wire\\:click]',row).find(a=>a.getAttribute('wire:click')===`updateQuantity(${p.id}, '${plus?'increment':'decrement'}')`));
          await wait(()=>Number(text(counter()))===qty+(plus?1:-1));
        }
        if(Number(text(counter()))!==p.packs)throw issue('Naivas quantity could not be verified.');
      }
      return {ok:true};
    }
    if(phase==='verify' && store==='carrefour') {
      // Same widget shapes used by the server cart verifier, but preserve other existing items.
      await wait(()=>document.querySelector('main [data-testid="expanded-widget"], [id^="entries-"] [role="combobox"]'));
      for(const p of products) {
        const row=await wait(()=>{
          const anchor=all('main a[href*="/p/"]').find(a=>path(a.href).endsWith('/p/'+p.id) && !a.closest('.group'));
          let row=anchor?.parentElement;
          while(row && row.tagName!=='MAIN' && !row.querySelector('[data-testid="expanded-widget"],[role="combobox"]'))row=row.parentElement;
          return row && row.tagName!=='MAIN' ? row : null;
        });
        const widget=row.querySelector('[data-testid="expanded-widget"]');
        const counter=(widget || row.querySelector('[role="combobox"]')).cloneNode(true);counter.querySelectorAll('button').forEach(el=>el.remove());
        if(Number(text(counter))!==p.packs)throw issue('Carrefour cart quantity does not match your selection.');
        const total=row.querySelector('.items-baseline');
        if(total && cents(priceText(total))!==expected(p)*BigInt(p.packs))throw issue('Carrefour changed a selected price. Review it before continuing.');
      }
      return {ok:true};
    }
    throw issue('Unsupported cart step.');
  } catch(error) {return {error:(error.expected ? error.message : 'The store layout changed or a control is unavailable. Inspect the store cart before resuming.').slice(0,500)};}
  finally {globalThis.__shoppingAgentCartBusy=false;}
}
