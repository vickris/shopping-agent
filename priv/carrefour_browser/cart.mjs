// Prepare exactly the selected guest cart. Never click checkout, place an order,
// submit credentials or payment details. Keep this browser session for the user.
import readline from "node:readline";
process.env.PLAYWRIGHT_BROWSERS_PATH ||= "0";
delete process.env.OPENAI_API_KEY;
delete process.env.ANTHROPIC_API_KEY;
const input = readline.createInterface({ input: process.stdin });
const plan = await new Promise(resolve => input.once("line", line => resolve(JSON.parse(line))));
let browser, page, finished = false, phase = "launch";
const emit = event => process.stdout.write(JSON.stringify(event) + "\n");
const finish = event => { if (!finished) { finished = true; emit(event); } };
input.on("line", async line => {
  try {
    const command = JSON.parse(line);
    if (command.action === "open") await page?.bringToFront();
    if (command.action === "close") { await browser?.close(); process.exit(0); }
  } catch { /* Ignore invalid commands; never execute arbitrary input. */ }
});
input.on("close", async () => { await browser?.close(); process.exit(0); });

function cents(value) {
  const match = String(value).replaceAll(",", "").trim().match(/^(\d+)(?:\.(\d{1,2}))?$/);
  if (!match) throw new Error("invalid_price");
  return BigInt(match[1]) * 100n + BigInt((match[2] || "").padEnd(2, "0"));
}
async function navigate(url) {
  const response = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 25000 });
  if (!response?.ok()) throw new Error("store_unavailable");
}
try {
  if (plan.store !== "carrefour" || !Array.isArray(plan.products) || plan.products.length === 0) throw new Error("invalid_basket");
  for (const p of plan.products) {
    const url = new URL(p.url);
    if (!/^\d+$/.test(p.id) || url.protocol !== "https:" || !["www.carrefour.ke", "carrefour.ke"].includes(url.hostname) || !url.pathname.endsWith("/p/" + p.id) || !Number.isInteger(p.packs) || p.packs < 1 || p.packs > 50) throw new Error("invalid_basket");
    cents(p.expected_price);
  }
  const { firefox } = await import("playwright");
  browser = await firefox.launch({ headless: process.argv.includes("--test"), timeout: 30000 });
  browser.on("disconnected", () => { emit({ status: "closed", message: "The Carrefour cart window was closed." }); process.exit(0); });
  const context = await browser.newContext();
  page = await context.newPage();
  for (let index = 0; index < plan.products.length; index++) {
    const product = plan.products[index];
    emit({status: "preparing", message: `Adding ${index + 1} of ${plan.products.length}: ${product.name}`});
    phase = "product";
    await navigate(product.url);
    if (!new URL(page.url()).pathname.endsWith("/p/" + product.id)) throw new Error("product_redirected");
    const panel = page.locator("main > div.relative.grid").filter({has: page.getByRole("heading", {level:1})});
    const controls = panel.locator("div.flex.flex-col.gap-sm").filter({has:page.getByText("Get It Delivered By", {exact:true})});
    await controls.getByRole("button", {name:"Add to cart", exact:true}).waitFor({state:"visible", timeout:20000});
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
    await controls.getByRole("button", {name: "Add to cart", exact:true}).click({timeout:10000});
    phase = "quantity";
    const quantity = controls.getByRole("combobox");
    await quantity.waitFor({state:"visible", timeout:10000});
    if ((await quantity.innerText()).trim() !== "1") throw new Error("cart_mismatch");
    for (let q = 2; q <= product.packs; q++) {
      await controls.locator('button.absolute.right-0.top-0:has(svg[data-testid="plus-icon"])').click({timeout:10000});
      await quantity.filter({hasText:new RegExp("^" + q + "$")}).waitFor({state:"visible", timeout:10000});
    }
  }
  phase = "verify_cart";
  await navigate("https://www.carrefour.ke/mafken/en/app/cart");
  await page.locator("[id^='entries-'] [role='combobox']").first().waitFor({state:"visible", timeout:15000});
  const rows = page.locator("[id^='entries-'] div.relative.rounded-xl").filter({has:page.getByRole("combobox")});
  // Cart controls become visible before their guest-session quantities load.
  // Wait for the exact snapshot instead of treating the loading state as failure.
  await page.waitForFunction(expected => {
    const rows = Array.from(document.querySelectorAll("[id^='entries-'] div.relative.rounded-xl"))
      .filter(row => row.querySelector('[role="combobox"]'));
    return rows.length === expected.length && expected.every(p => rows.some(row => {
      const link = row.querySelector('a[href*="/p/"]');
      return link && new URL(link.href).pathname.endsWith("/p/" + p.id)
        && row.querySelector('[role="combobox"]').textContent.trim() === String(p.packs);
    }));
  }, plan.products.map(p => ({id:p.id, packs:p.packs})), {timeout:20000}).catch(() => {throw new Error("cart_mismatch");});
  if (await rows.count() !== plan.products.length) throw new Error("cart_mismatch");
  for (const p of plan.products) {
    const row = rows.filter({has: page.locator(`a[href*="/p/${p.id}?"]`)});
    if (await row.count() !== 1 || (await row.getByRole("combobox").innerText()).trim() !== String(p.packs)) throw new Error("cart_mismatch");
  }
  const checkout = page.getByRole("button", {name:"Checkout",exact:true});
  const canCheckout = (await checkout.count()) > 0 && await checkout.first().isEnabled();
  finish({status: canCheckout ? "ready" : "needs_attention", verified: true,
    message: canCheckout ? "Your Carrefour cart is filled and verified. Review it and pay in the Carrefour browser window." : "Your Carrefour cart is filled and verified, but checkout is not available yet. Review the store’s minimum-order or delivery requirements in the Carrefour window.",
    estimated_total: plan.estimated_total, product_count: plan.products.length});
  await page.bringToFront();
} catch (error) {
  if (process.argv.includes("--test")) process.stderr.write(phase + ": " + error.message + "\n");
  const messages = {
    price_changed: "A Carrefour price changed. Review the partially filled cart before continuing.",
    cart_mismatch: "Carrefour’s cart did not match the selected products and pack counts. Review the cart manually.",
    invalid_basket: "The selected Carrefour basket is invalid.",
    store_unavailable: "Carrefour is unavailable. The cart could not be verified."
  };
  finish({status:"failed", verified:false, message:messages[error.message] || "Cart preparation stopped before verification. Review the Carrefour window for stock, connection or login requirements."});
  // Keep a partial cart visible for inspection; never claim it is ready to pay.
  if (page) await page.bringToFront().catch(() => {});
  else process.exit(1);
}
// Parent owns the 30-minute session expiry. Keep stdin open for handoff commands.
