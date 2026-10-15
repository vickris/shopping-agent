// Account handoff uses storefront UI only. Never read credentials or copy cookies.
export const carrefourCartUrl = 'https://www.carrefour.ke/mafken/en/app/cart';
export const carrefourLoginUrl = 'https://www.carrefour.ke/mafken/en/login?redirect=/mafken/en/app/cart';

export function compatibleCart(rows, products) {
  const expected = new Map(products.map(p => [p.id, p.packs]));
  const seen = new Set();
  return rows.every(row => {
    if (seen.has(row.id)) return false;
    seen.add(row.id);
    return expected.has(row.id) && Number.isInteger(row.packs) && row.packs > 0 && row.packs <= expected.get(row.id);
  });
}

export async function readCarrefourCart(page) {
  // Both empty and populated carts render inside main; wait for hydration before
  // declaring an empty cart. A timed-out render must never authorize additions.
  await page.waitForFunction(() => {
    const main = document.querySelector('main');
    return main && (main.querySelector("[id^='entries-'] [role='combobox']") ||
      /your cart is empty|your shopping cart is empty|cart is empty/i.test(main.textContent));
  }, null, {timeout:20000});
  return page.locator("[id^='entries-'] div.relative.rounded-xl").filter({has:page.getByRole('combobox')}).evaluateAll(rows => rows.map(row => {
    const link = row.querySelector('a[href*="/p/"]');
    const id = link && new URL(link.href).pathname.match(/\/p\/(\d+)$/)?.[1];
    const packs = Number(row.querySelector('[role="combobox"]').textContent.trim());
    return {id,packs};
  }));
}

export async function signInCarrefour({page,navigate,pause,products}) {
  await navigate(carrefourLoginUrl);
  await pause('Sign in to your Carrefour account in the store window, including any OTP. Return to the store after signing in, then click “I’m signed in — continue”.', 'sign_in');
  for (;;) {
    await navigate(carrefourCartUrl);
    const rows = await readCarrefourCart(page);
    const login = page.getByRole('link',{name:'Login & Register',exact:true});
    if (new URL(page.url()).pathname.includes('/login') || await login.isVisible()) {
      await navigate(carrefourLoginUrl);
      await pause('Carrefour still shows you as signed out. Finish signing in in its window, then continue.', 'sign_in');
      continue;
    }
    if (!compatibleCart(rows,products)) {
      await pause('Your Carrefour account cart contains extra items or higher quantities. Review it in the store window and adjust it to this selected basket before continuing. The app will not remove existing items.', 'review_cart');
      continue;
    }
    return;
  }
}

export async function confirmPhoneCart({pause, result}) {
  const answer = await pause('Your Carrefour account cart is filled and verified in this browser. On your phone, sign in to the same Carrefour account and open its cart. Check the products and pack counts, then confirm here whether they appeared.', 'phone_check', true);
  return {...result, status:'needs_attention', sync_status:answer === 'sync-missing' ? 'not_seen' : 'user_confirmed',
    message: answer === 'sync-missing'
      ? 'Your Carrefour cart is verified in the store window, but you reported that it did not appear on your phone. Cross-device synchronisation is not confirmed. You can continue in the store window.'
      : 'You confirmed that the Carrefour basket appeared on your phone. Review delivery details, final prices and pay directly with Carrefour.'};
}
