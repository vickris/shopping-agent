// Self-contained: Chrome serializes this function into an ISOLATED world.
// Only visible cart controls are used. Never click sign-in, checkout or payment.
export async function cartStep({store,product,products,phase,branch,readonly=false,exact=false}) {
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
    const modernLocation=store==='naivas' && all('button[data-slot="dropdown-menu-trigger"]').find(el=>visible(el)&&el.querySelector('span.truncate'));
    if(modernLocation) {
      const label=text(modernLocation);
      if(phase==='probe') {
        if(!label || /^Nairobi,?\s*Kenya$|select.*address|your address/i.test(label))throw issue('Select your delivery address on Naivas, then resume preparation here.');
        return {ok:true,layout:'react'};
      }
      const sheet=()=>all('[role="dialog"][data-slot="sheet-content"]').find(el=>visible(el)&&/Shopping Cart/i.test(text(el)));
      const cartButton=()=>all('button[data-slot="button"]').find(el=>visible(el)&&!el.closest('main,[role="dialog"]')&&/^\d+$/.test(text(el))&&el.querySelector('svg'));
      const openCart=async()=>{if(!sheet())click(cartButton());await wait(sheet);return sheet();};
      const closeCart=async()=>{if(sheet())click(sheet().querySelector('button[data-slot="sheet-close"]'));await wait(()=>!sheet());};
      const rows=()=>sheet()?[...new Set(all('button[aria-label="Open quantity selection modal"]',sheet()).filter(visible).map(counter=>{
        let row=counter.parentElement;
        while(row && row!==sheet() && (!row.querySelector('img[src*="/product/"]') || !row.querySelector('p.truncate')))row=row.parentElement;
        return row && row!==sheet()?row:null;
      }).filter(Boolean))]:[];
      const rowId=row=>row?.querySelector('img[src*="/product/"]')?.getAttribute('src').match(/\/product\/(\d+)\//)?.[1];
      const rowFor=p=>rows().find(row=>rowId(row)===p.id);
      const quantity=row=>{const value=text(row?.querySelector('button[aria-label="Open quantity selection modal"]'));return /^\d+$/.test(value)?Number(value):NaN;};
      const rowPrice=row=>priceText(all('p',row).find(el=>/^KES\s/i.test(text(el))));
      const empty=()=>sheet() && /Your cart is empty/i.test(text(sheet())) && rows().length===0;
      if(phase==='clear') {
        await openCart();
        await wait(()=>rows().length || empty());
        if(empty())return {ok:true};
        click(all('button[data-slot="button"]',sheet()).find(el=>visible(el)&&text(el)==='Clear Cart'));
        const confirmation=await wait(()=>all('[role="dialog"]').find(el=>visible(el)&&all('button',el).some(button=>text(button)==='Yes, clear cart')));
        click(all('button',confirmation).find(el=>text(el)==='Yes, clear cart'));
        await wait(empty);return {ok:true};
      }
      if(phase==='items') {
        if(path(location.href)!==path(product.url))throw issue('Naivas redirected to a different product.');
        const heading=await wait(()=>document.querySelector('main h1'));
        if(text(heading).toLowerCase().replace(/\s+/g,' ')!==product.name.toLowerCase().replace(/\s+/g,' '))throw issue('Naivas returned a different product name.');
        await wait(()=>all('main img[src*="/product/"]').some(img=>img.getAttribute('src').includes('/product/'+product.id+'/')));
        checkPrice(priceText(heading.parentElement.querySelector('div.font-semibold')),product);
        await openCart();await wait(()=>rows().length || empty());
        if(!rowFor(product)) {
          await closeCart();const before=Number(text(cartButton()));
          click(all('main button').find(el=>visible(el)&&/^Add to Cart$/i.test(text(el))));
          await wait(()=>Number(text(cartButton()))>before);
          await openCart();await wait(()=>rowFor(product));
        }
        for(let attempt=0;attempt<50;attempt++) {
          const row=await wait(()=>rowFor(product));const qty=quantity(row);
          if(!Number.isInteger(qty)||qty<1)throw issue('Could not read the Naivas cart quantity.');
          checkPrice(rowPrice(row),product);
          if(qty===product.packs)return {ok:true};
          const plus=qty<product.packs;
          click(row.querySelector(`button[aria-label="${plus?'Increase':'Decrease'} quantity"]`));
          await wait(()=>quantity(rowFor(product))===qty+(plus?1:-1));
        }
        throw issue('Naivas quantity limit reached.');
      }
      if(phase==='verify') {
        await openCart();await wait(()=>rows().length || empty());
        const actual=rows();
        if(exact && (actual.length!==products.length || new Set(actual.map(rowId)).size!==products.length || actual.some(row=>!products.some(p=>p.id===rowId(row)))))throw issue('Naivas cart contains missing or extra products.');
        for(const p of products) {
          const row=rowFor(p);
          if(!row || quantity(row)!==p.packs)throw issue('Naivas cart quantity does not match your selection.');
          checkPrice(rowPrice(row),p);
        }
        return {ok:true};
      }
      throw issue('Unsupported Naivas cart step.');
    }
    if(phase==='probe') {
      if(store==='quickmart') {
        const address=await wait(()=>all('.js-location-address').find(el=>visible(el)&&text(el)&&!/enter your delivery address/i.test(text(el)))).catch(()=>{throw issue('Set your delivery address on Quickmart, then resume preparation here.');});
        const links=all('a[href]');
        const id=links.map(a=>a.getAttribute('href').match(/\/shops\/report-spam\/(\d+)/)?.[1]).find(Boolean) || links.filter(a=>a.matches('.navigation-link')).map(a=>a.getAttribute('href').match(/^\/(\d+)\/?$/)?.[1]).find(Boolean);
        if(!id)throw issue('Choose and open your Quickmart branch first.');
        return {ok:true,branch:id};
      }
      if(store==='naivas') {
        if(document.querySelector('button[data-slot="button"]') && !document.querySelector('.geoLocation'))throw issue('Naivas has changed its website layout. Automatic checkout needs an adapter update; add the selected products on its website for now.');
        await wait(()=>all('.geoLocation').find(el=>visible(el)&&text(el)&&!/select location|choose location|enter your/i.test(text(el)))).catch(()=>{throw issue('Set your delivery address on Naivas, then resume preparation here.');});
      }
      return {ok:true};
    }
    const cartRows=()=>{
      if(store==='quickmart')return all('#sideCartJs li.list-cart-item').filter(visible);
      if(store==='naivas')return all('div.rounded-xl.p-4.w-full').filter(el=>visible(el)&&el.querySelector('span[x-text="quantity"]'));
      return [...new Set(all('main [data-testid="expanded-widget"],main [id^="entries-"] [role="combobox"]').filter(visible).map(widget=>{
        let row=widget.parentElement;
        while(row && row.tagName!=='MAIN' && (!row.querySelector('a[href*="/p/"]') || !row.querySelector('.items-baseline')))row=row.parentElement;
        return row && row.tagName!=='MAIN' && !row.closest('.group') ? row : null;
      }).filter(Boolean))];
    };
    const cartQuantity=row=>{
      if(store==='quickmart')return Number(text(row.querySelector('.selected-quantity')).match(/^Quantity:\s*(\d+)$/)?.[1]);
      if(store==='naivas'){const value=text(row.querySelector('span[x-text="quantity"]'));return /^\d+$/.test(value)?Number(value):NaN;}
      const copy=row.querySelector('[data-testid="expanded-widget"],[role="combobox"]')?.cloneNode(true);
      copy?.querySelectorAll('button').forEach(button=>button.remove());
      // Legacy quantity selectors are themselves buttons.
      return /^\d+$/.test(text(copy))?Number(text(copy)):NaN;
    };
    const emptyCart=()=>{const root=store==='quickmart'?document.querySelector('#sideCartJs'):document.querySelector('main') || document.body;return visible(root) && /your (?:shopping )?(?:cart|basket) is (?:currently )?empty|(?:cart|basket) is (?:currently )?empty/i.test(root.innerText || '');};
    const cartKey=row=>store==='carrefour'
      ? all('a[href*="/p/"]',row).map(a=>path(a.href).match(/\/p\/([^/]+)$/)?.[1]).find(Boolean)
      : store==='naivas' ? all('a[wire\\:click]',row).map(a=>a.getAttribute('wire:click').match(/^redirectToProductPage\((\d+)\)$/)?.[1]).find(Boolean)
      : all('a.product-profile-title',row).map(a=>path(a.href)).find(Boolean);
    const settledRows=()=>{const rows=cartRows();return rows.length?rows.every(row=>Number.isInteger(cartQuantity(row))&&cartQuantity(row)>0)?rows:null:emptyCart()?[]:null;};
    if(phase==='clear') {
      if(store==='carrefour' && !location.pathname.endsWith('/app/cart') || store==='naivas' && location.pathname!=='/cart/index')throw issue('Open the supermarket cart before replacing it.');
      if(store==='quickmart') {
        if(!visible(document.querySelector('#sideCartJs')))click(all('button.button-cart').find(visible));
        await wait(()=>visible(document.querySelector('#sideCartJs')));
      }
      for(let step=0;step<500;step++) {
        const rows=await wait(settledRows);
        if(!rows.length) {await wait(emptyCart);return {ok:true};}
        const row=rows[0],qty=cartQuantity(row);
        if(!Number.isInteger(qty)||qty<1)throw issue('Could not read an old cart item. Empty the cart manually, then resume.');
        let remove;
        if(store==='carrefour')remove=row.querySelector('button[aria-label="Decrease quantity"],button[aria-label="Remove item"],button[aria-label="Remove"]') || row.querySelector('svg[data-testid="minus-icon"],svg[data-testid="delete-icon"],svg[data-testid="trash-icon"]')?.closest('button');
        else if(store==='naivas') {
          const id=all('a[wire\\:click]',row).map(a=>a.getAttribute('wire:click').match(/^redirectToProductPage\((\d+)\)$/)?.[1]).find(Boolean);
          if(!id)throw issue('Could not identify an old Naivas cart item. Empty the cart manually, then resume.');
          remove=all('a[wire\\:click]',row).find(a=>a.getAttribute('wire:click')===`updateQuantity(${id}, 'decrement')`);
        } else remove=all('button,a',row).find(el=>/^remove(?:\b|$)|^delete$/i.test(el.getAttribute('aria-label') || el.getAttribute('title') || text(el)));
        if(!remove)throw issue('The store does not expose a supported remove control. Empty its cart manually, then resume; no new items were added.');
        const key=cartKey(row);if(!key)throw issue('Could not identify an old cart item. Empty the cart manually, then resume.');
        click(remove);
        await wait(()=>{
          const updated=settledRows();if(!updated)return false;
          const current=updated.find(item=>cartKey(item)===key);
          return !current || cartQuantity(current)<qty;
        });
      }
      throw issue('The old cart is too large to clear automatically. Empty it manually, then resume.');
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
        const button=icon?.closest('button');
        if(plus && button?.disabled)throw issue(`Carrefour currently allows only ${qty} pack(s) of ${product.name}; you selected ${product.packs}. Reduce the quantity and send a new order.`);
        click(button);
        await wait(()=>Number(text(counter()))===qty+(plus?1:-1));
      }
      throw issue('Quantity limit reached.');
    }
    if(phase==='items' && store==='quickmart') {
      if(path(location.href)!==path(product.url))throw issue('Quickmart redirected to a different product.');
      const card=await wait(()=>all('.product-description').find(el=>el.querySelector('h1') && all('#frmBuyProduct input.qty-input',el).some(input=>input.dataset.key===product.id)) || all('.productInfoJs').find(el=>all('input.qty-input',el).some(input=>input.dataset.key===product.id)));
      const sellerBranch=all('a[href]',card).map(a=>a.getAttribute('href').match(/^\/shops\/send-message\/(\d+)\//)?.[1]).find(Boolean);
      if(sellerBranch && sellerBranch!==branch)throw issue('This product belongs to another Quickmart branch. Compare products for the branch selected on its website.');
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
      if(path(location.href)!==path(product.url))throw issue('Naivas redirected to a different product.');
      const card=await wait(()=>all('div.border-naivas-bg').filter(el=>all('input[name="product_id"]',el).some(input=>input.value===product.id)).sort((a,b)=>a.querySelectorAll('*').length-b.querySelectorAll('*').length)[0]);
      checkPrice(text(card.querySelector('.product-price span.font-bold')),product);
      await new Promise(r=>setTimeout(r,750));
      const counter=()=>all('button',card).find(el=>visible(el)&&/^\d+$/.test(text(el)));
      if(!counter()) {
        click(all('form button',card).find(el=>visible(el)&&/ADD TO CART/i.test(text(el))));
        await wait(()=>counter());
      }
      return {ok:true};
    }
    if(phase==='verify' && exact) {
      if(store==='quickmart' && !visible(document.querySelector('#sideCartJs')))click(all('button.button-cart').find(visible));
      const rows=await wait(settledRows);
      const keys=rows.map(cartKey);
      const wanted=products.map(p=>store==='quickmart'?path(p.url):p.id);
      if(rows.length!==products.length || new Set(keys).size!==products.length || keys.some(key=>!wanted.includes(key)))throw issue('The supermarket cart contains missing or extra products. Review it before paying; this order is not verified.');
    }
    if(phase==='verify' && store==='quickmart') {
      if(!visible(document.querySelector('#sideCartJs')))click(all('button.button-cart').find(visible));
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
        const row=await wait(()=>cartRows().find(el=>all('a[wire\\:click]',el).some(a=>a.getAttribute('wire:click')===`redirectToProductPage(${p.id})`)));
        const counter=()=>row.querySelector('span[x-text="quantity"]');
        await wait(()=>/^\d+$/.test(text(counter())));
        for(let n=0;n<50;n++) {
          const qty=Number(text(counter()));if(!Number.isInteger(qty)||qty<1)throw issue('Could not read the cart quantity.');
          if(cents(text(row.querySelector('.font-extrabold')))!==expected(p)*BigInt(qty))throw issue('Naivas changed a selected price. Review it before continuing.');
          if(qty===p.packs)break;
          if(readonly)throw issue('Naivas cart quantity changed outside this transfer. Review it before continuing.');
          const plus=qty<p.packs;
          click(all('a[wire\\:click]',row).find(a=>a.getAttribute('wire:click')===`updateQuantity(${p.id}, '${plus?'increment':'decrement'}')`));
          await wait(()=>Number(text(counter()))===qty+(plus?1:-1));
        }
        if(Number(text(counter()))!==p.packs)throw issue('Naivas quantity could not be verified.');
      }
      return {ok:true};
    }
    if(phase==='verify' && store==='carrefour') {
      await wait(settledRows);
      for(const p of products) {
        const row=await wait(()=>cartRows().find(row=>all('a[href*="/p/"]',row).some(a=>path(a.href).endsWith('/p/'+p.id))));
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
