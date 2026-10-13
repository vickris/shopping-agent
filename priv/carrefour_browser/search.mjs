// Fetch the public search page in an isolated, temporary browser context.
// Product interpretation stays in the existing Elixir ResponseParser.
const query = process.argv[2];
process.env.PLAYWRIGHT_BROWSERS_PATH ||= "0";
const store = process.argv[3] || "carrefour";
let browser;
let completed = false;

function finish(result, code = 0) {
  if (completed) return;
  completed = true;
  process.stdout.write(JSON.stringify(result));
  process.exitCode = code;
}

const deadline = setTimeout(async () => {
  finish({ error: "browser_timeout" }, 1);
  await browser?.close().catch(() => {});
  process.exit(1);
}, 45000);

try {
  if (!["carrefour", "quickmart", "naivas"].includes(store)) throw new Error("unsupported_store");
  if (!query?.trim()) throw new Error("invalid_query");
  const { chromium, firefox } = await import("playwright");
  const engine = process.env.DEAL_AGENT_BROWSER_ENGINE || (store === "quickmart" ? "chromium" : "firefox");
  if (!["chromium", "firefox"].includes(engine)) throw new Error("unsupported_browser_engine");
  browser = await (engine === "firefox" ? firefox : chromium).launch({
    headless: true,
    ...(engine === "chromium" ? { channel: process.env.DEAL_AGENT_BROWSER_CHANNEL || "chromium" } : {}),
    ...(engine === "chromium"
      ? { args: process.env.DEAL_AGENT_BROWSER_HTTP1 === "1" ? ["--disable-http2"] : [] }
      : { firefoxUserPrefs: process.env.DEAL_AGENT_BROWSER_HTTP1 === "1" ? { "network.http.http2.enabled": false } : {} }),
    timeout: 10000,
  });
  const context = await browser.newContext();
  const page = await context.newPage();
  const url = store === "quickmart"
    ? new URL("https://www.quickmart.co.ke/shops/products/1/keyword-" + encodeURIComponent(query.trim()))
    : new URL(store === "naivas" ? "https://www.naivas.online/search" : "https://www.carrefour.ke/mafken/en/search");
  if (store === "naivas") url.searchParams.set("term", query.trim());
  if (store === "carrefour") url.searchParams.set("keyword", query.trim());
  const response = await page.goto(url.href, { waitUntil: "domcontentloaded", timeout: 25000 });
  if (!response || !response.ok()) {
    finish({ error: "browser_http_error", status: response?.status() ?? null }, 1);
  } else {
    // Wait for real product cards or the explicit empty state. A blank page,
    // a challenge or a timeout must never become an empty search result.
    await page.locator(store === "quickmart"
      ? "#products-listing .productInfoJs, #frmProductSearchPaging input[name='recordDisplayCount'][value='0']"
      : store === "naivas" ? "div.border-naivas-bg a span.line-clamp-2, h2:has-text('0 Search Results Found')"
      : "div.group a[href*='/p/'] span.line-clamp-2, img[src*='no-result-found.svg']")
      .first().waitFor({ state: "attached", timeout: 12000 });
    finish({ html: await page.content() });
  }
} catch (error) {
  const message = error?.message ?? "";
  if (process.env.CARREFOUR_BROWSER_DEBUG === "1") process.stderr.write(message + "\n");
  const kind = message.includes("ERR_HTTP2_PROTOCOL_ERROR") ? "browser_http2_error"
    : error?.code === "ERR_MODULE_NOT_FOUND" ? "browser_dependency_missing"
    : message.includes("Executable doesn't exist") ? "browser_not_installed"
    : error?.name === "TimeoutError" ? "browser_timeout"
    : "browser_search_failed";
  finish({ error: kind }, 1);
} finally {
  await browser?.close().catch(() => {});
  clearTimeout(deadline);
}
