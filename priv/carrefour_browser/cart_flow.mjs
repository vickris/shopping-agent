import {verifyCarrefourCart} from './carrefour_cart.mjs';
export async function fillCart({page,plan,navigate,cents,pause,emit}) {
  if (plan.store !== "carrefour") {
    const {prepareStore} = await import("./store_carts.mjs");
    return await prepareStore({page,plan,navigate,cents,pause,emit});
  } else {
  for (let index = 0; index < plan.products.length; index++) {
    const product = plan.products[index];
    emit({status: "preparing", message: `Adding ${index + 1} of ${plan.products.length}: ${product.name}`});

    await navigate(product.url);
    if (!new URL(page.url()).pathname.endsWith("/p/" + product.id)) throw new Error("product_redirected");
    const panel = page.locator("main > div.relative.grid").filter({has: page.getByRole("heading", {level:1})});
    const controls = panel.locator("div.flex.flex-col.gap-sm").filter({has:page.getByText("Get It Delivered By", {exact:true})});
    await page.waitForFunction(() => {
      const panel=document.querySelector("main > div.relative.grid");
      return panel && (panel.querySelector('[role="combobox"]') || Array.from(panel.querySelectorAll("button")).some(b=>b.textContent.trim()==="Add to cart"));
    }, null, {timeout:20000});
    if (index === 0) {
      const cookies = page.getByRole("button", {name: "Accept All Cookies", exact:true});
      await cookies.waitFor({state:"visible", timeout:3000}).then(() => cookies.click()).catch(() => {});
    }
    const price = await panel.locator(".force-ltr").first().evaluate(el => {
      const copy = el.cloneNode(true);
      copy.querySelectorAll("del,s,.line-through").forEach(node => node.remove());
      return copy.textContent.trim().replace(/^KES\s*/, "").replace(/\s/g, "");
    });
    if (cents(price) !== cents(product.expected_price)) throw new Error("price_changed");
    const quantity = controls.getByRole("combobox");
    let current = 0;
    if (plan.mode === "account" && await quantity.isVisible()) {
      current = Number((await quantity.innerText()).trim());
      if (!Number.isInteger(current) || current < 1 || current > product.packs) throw new Error("cart_mismatch");
    } else {
      await controls.getByRole("button", {name: "Add to cart", exact:true}).click({timeout:10000});
      await quantity.waitFor({state:"visible", timeout:10000});
      if ((await quantity.innerText()).trim() !== "1") throw new Error("cart_mismatch");
      current = 1;
    }

    for (let q = current + 1; q <= product.packs; q++) {
      await controls.locator('button.absolute.right-0.top-0:has(svg[data-testid="plus-icon"])').click({timeout:10000});
      await quantity.filter({hasText:new RegExp("^" + q + "$")}).waitFor({state:"visible", timeout:10000});
    }
  }

  await navigate("https://www.carrefour.ke/mafken/en/app/cart");
  // Wait for hydrated SKU quantities and current line totals, not an obsolete
  // entries-* container or quantity dropdown.
  await verifyCarrefourCart(page, plan.products, cents);
  const checkout = page.getByRole("button", {name:/^Checkout(?:\s*\(.*\))?$/i});
  const canCheckout = (await checkout.count()) > 0 && await checkout.first().isEnabled();
  let result = {status: canCheckout ? "ready" : "needs_attention", verified: true,
    message: canCheckout ? "Your Carrefour cart is filled and verified. Review it and pay in the Carrefour browser window." : "Your Carrefour cart is filled and verified, but checkout is not available yet. Review the store’s minimum-order or delivery requirements in the Carrefour window.",
    estimated_total: plan.estimated_total, product_count: plan.products.length};
  return result;
  }
}
