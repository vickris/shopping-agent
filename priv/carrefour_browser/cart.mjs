// Prepare exactly the selected guest cart. Never click checkout, place an order,
// submit credentials or payment details. Keep this browser session for the user.
import readline from "node:readline";
process.env.PLAYWRIGHT_BROWSERS_PATH ||= "0";
delete process.env.OPENAI_API_KEY;
delete process.env.ANTHROPIC_API_KEY;
const input = readline.createInterface({ input: process.stdin });
const plan = await new Promise(resolve => input.once("line", line => resolve(JSON.parse(line))));
let browser, page, resume, pauseStep, finished = false, phase = "launch";
const label = {carrefour:"Carrefour",quickmart:"Quickmart",naivas:"Naivas"}[plan.store];
async function pause(message, step = "store_prompt", verified = false) {
  pauseStep = step;
  const pending = new Promise(resolve => { resume = resolve; });
  emit({status:"awaiting_input",verified,step,message});
  await page.bringToFront();
  const action = await pending;
  pauseStep = undefined;
  emit({status:"preparing",message:"Continuing cart preparation."});
  return action;
}
const emit = event => process.stdout.write(JSON.stringify(event) + "\n");
const finish = event => { if (!finished) { finished = true; emit(event); } };
input.on("line", async line => {
  try {
    const command = JSON.parse(line);
    if ((command.action === "resume" || (command.action === "sync-missing" && pauseStep === "phone_check")) && resume) { const next = resume; resume = undefined; next(command.action); }
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
  const response = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45000 });
  if (!response?.ok()) throw new Error("store_unavailable");
}
try {
  if (!label || !Array.isArray(plan.products) || plan.products.length === 0) throw new Error("invalid_basket");
  if (plan.mode && !["guest", "account"].includes(plan.mode) || plan.mode === "account" && plan.store !== "carrefour") throw new Error("invalid_basket");
  for (const p of plan.products) {
    const url = new URL(p.url);
    const domain = {carrefour:"carrefour.ke",quickmart:"quickmart.co.ke",naivas:"naivas.online"}[plan.store];
    if (!/^\d+$/.test(p.id) || url.protocol !== "https:" ||
        ![domain, `www.${domain}`].includes(url.hostname) || url.username || url.password || url.port ||
        (plan.store === "carrefour" && !url.pathname.endsWith("/p/" + p.id)) ||
        (plan.store !== "carrefour" && (!p.query || !url.pathname || url.pathname === "/")) ||
        !Number.isInteger(p.packs) || p.packs < 1 || p.packs > 50) throw new Error("invalid_basket");
    cents(p.expected_price);
  }
  const { firefox, chromium } = await import("playwright");
  browser = await (plan.store === "quickmart" ? chromium : firefox).launch({ headless: process.argv.includes("--test"), ...(plan.store === "quickmart" ? {channel:"chromium"} : {}), timeout: 30000 });
  browser.on("disconnected", () => { emit({ status: "closed", message: `The ${label} cart window was closed.` }); process.exit(0); });
  const context = await browser.newContext();
  page = await context.newPage();
  const {fillCart} = await import("./cart_flow.mjs");
  finish(await fillCart({page,plan,navigate,cents,pause,emit}));
} catch (error) {
  if (process.argv.includes("--test")) process.stderr.write(phase + ": " + error.message + "\n");
  const messages = {
    price_changed: "A Carrefour price changed. Review the partially filled cart before continuing.",
    cart_mismatch: "Carrefour’s cart did not match the selected products and pack counts. Review the cart manually.",
    invalid_basket: "The selected Carrefour basket is invalid.",
    wrong_branch: "Quickmart requires the Ruaka store for this basket. Close this cart and search again for another branch.",
    store_unavailable: "Carrefour is unavailable. The cart could not be verified."
  };
  finish({status:"failed", verified:false, message: (messages[error.message] || "Cart preparation stopped before verification. Review the Carrefour window for stock, connection or login requirements.").replaceAll("Carrefour",label || "Store")});
  // Keep a partial cart visible for inspection; never claim it is ready to pay.
  if (page) await page.bringToFront().catch(() => {});
  else process.exit(1);
}
// Parent owns the 30-minute session expiry. Keep stdin open for handoff commands.
