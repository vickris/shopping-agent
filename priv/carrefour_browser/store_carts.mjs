// Store adapters use visible storefront controls only. Never submit checkout.
export async function prepareStore({page, plan, navigate, cents, pause, emit}) {
  const price = text => cents(text.replace(/KES|KSh|\s|,/gi, ''));
  const wait = async predicate => {
    for (let i = 0; i < 80; i++) {
      if (await predicate()) return;
      await page.waitForTimeout(250);
    }
    throw new Error('cart_mismatch');
  };
  if (plan.store === 'quickmart') {
    await navigate('https://www.quickmart.co.ke/shops/products/1/keyword-milk');
    const locationSet = async () => {
      const text = await page.locator('.js-location-address').first().innerText();
      return text.trim() && !/enter your delivery address/i.test(text);
    };
    while (!await locationSet()) {
      if (!await page.locator('#location_fld').isVisible()) await page.locator('.locationButtonJs').first().click();
      await pause('Enter your delivery location in the Quickmart window, choose the Ruaka store, then click Continue here.');
    }
    if (!await page.locator('a[href="/ruaka"]').count()) throw new Error('wrong_branch');
    for (const p of plan.products) {
      emit({status:'preparing', message:`Adding ${p.name} to Quickmart.`});
      await navigate('https://www.quickmart.co.ke/shops/products/1/keyword-' + encodeURIComponent(p.query));
      const card = page.locator('#products-listing .productInfoJs').filter({has:page.locator(`input.qty-input[data-key="${p.id}"]`)});
      if (await card.count() !== 1) throw new Error('cart_mismatch');
      const href = await card.locator('a.products-title').getAttribute('href');
      if (new URL(href,page.url()).pathname !== new URL(p.url).pathname) throw new Error('cart_mismatch');
      if (price(await card.locator('.products-price-new').first().innerText()) !== cents(p.expected_price)) throw new Error('price_changed');
      const qty = card.locator('input.qty-input');
      if (await card.locator('.quantityBlockJs').isVisible()) throw new Error('cart_mismatch');
      await card.locator('button[name="btnAddToCart"]').click();
      await card.locator('.quantityBlockJs').waitFor({state:'visible',timeout:20000});
      for (let n=2;n<=p.packs;n++) {
        await card.locator('.increase-js').click();
        await wait(async()=> Number(await qty.inputValue()) === n);
      }
    }
    await page.locator('button.button-cart').click();
    const rows = page.locator('#sideCartJs li.list-cart-item');
    await wait(async()=> await rows.count() === plan.products.length);
    for (const p of plan.products) {
      const row = rows.filter({has:page.locator(`a.product-profile-title[href="${new URL(p.url).pathname}"]`)});
      await wait(async()=> await row.count()===1 && (await row.locator('.selected-quantity').innerText()).trim() === `Quantity: ${p.packs}`);
      if (price(await row.locator('.products-price-new').first().innerText()) !== cents(p.expected_price)) throw new Error('price_changed');
    }
  } else {
    for (const p of plan.products) {
      emit({status:'preparing',message:`Adding ${p.name} to Naivas.`});
      await navigate('https://www.naivas.online/search?term='+encodeURIComponent(p.query));
      await page.waitForFunction(() => Boolean(window.Livewire && window.Alpine), null, {timeout:20000});
      await page.waitForTimeout(750);
      const cookies = page.getByRole('button',{name:'Close without accepting cookies',exact:true});
      await cookies.click({timeout:2500}).catch(()=>{});
      const card = page.locator('div.border-naivas-bg').filter({has:page.locator(`a[href$="${new URL(p.url).pathname}"]`)});
      if (await card.locator(`input[name="product_id"][value="${p.id}"]`).count() !== 1) throw new Error('cart_mismatch');
      await card.first().waitFor({state:'visible',timeout:20000});
      if (await card.count()!==1) throw new Error('cart_mismatch');
      const link = card.locator('a').filter({has:page.locator('span.line-clamp-2')});
      if (new URL(await link.getAttribute('href'),page.url()).pathname!==new URL(p.url).pathname) throw new Error('cart_mismatch');
      if (price(await card.locator('.product-price span.font-bold').first().innerText())!==cents(p.expected_price)) throw new Error('price_changed');
      await card.locator('form[wire\\:submit="addToCart"] button').click();
      await card.getByRole('button',{name:'1',exact:true}).waitFor({state:'visible',timeout:20000});
    }
    await navigate('https://www.naivas.online/cart/index');
    for (const p of plan.products) {
      const row = page.locator('div.rounded-xl.p-4.w-full').filter({has:page.locator(`a[wire\\:click="redirectToProductPage(${p.id})"]`)});
      await row.first().waitFor({state:'visible',timeout:20000});
      if (await row.count()!==1) throw new Error('cart_mismatch');
      const qty=row.locator('span[x-text="quantity"]');
      await wait(async()=> (await qty.innerText()).trim()==='1');
      for(let n=2;n<=p.packs;n++) {
        await row.locator(`a[wire\\:click="updateQuantity(${p.id}, 'increment')"]`).first().click();
        await wait(async()=> (await qty.innerText()).trim()===String(n));
      }
    }
    await navigate('https://www.naivas.online/cart/index');
    const rows=page.locator('div.rounded-xl.p-4.w-full').filter({has:page.locator('a[wire\\:click^="updateQuantity("]')});
    await wait(async()=>await rows.count()===plan.products.length);
    for(const p of plan.products) {
      const row=rows.filter({has:page.locator(`a[wire\\:click="redirectToProductPage(${p.id})"]`)});
      await wait(async()=>await row.count()===1 && (await row.locator('span[x-text="quantity"]').innerText()).trim()===String(p.packs));
      if(price(await row.locator('.font-extrabold').first().innerText())!==cents(p.expected_price)*BigInt(p.packs)) throw new Error('price_changed');
    }
  }
  return {status:'needs_attention',verified:true,message:`Your ${plan.store==='quickmart'?'Quickmart':'Naivas'} cart is filled and verified. Review delivery details, sign in if required, and pay in the store window.`,estimated_total:plan.estimated_total,product_count:plan.products.length};
}
