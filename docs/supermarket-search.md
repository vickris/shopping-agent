# Supermarket search and selection

Each chat or manual shopping-list item searches Carrefour, Quickmart and Naivas independently
using isolated headless Firefox contexts for Carrefour and Naivas, and Chromium for Quickmart.
The Playwright runtime waits for rendered
product cards and returns page HTML to the store-specific Elixir parsers. No LLM
invents prices or calculates costs. HTTP clients remain available for explicit
injection and offline boundary tests; they are not the app's default transport.

Quickmart uses its public Ruaka branch listing:
`https://www.quickmart.co.ke/shops/products/1/keyword-milk`.
Only its initial page (normally 30 results) is fetched. Prices are the current
`.products-price-new` amounts, with old prices excluded. Stock must be positive
and the Add button enabled. Labelled sizes are extracted from titles; ambiguous
bundles keep nil size. Original card HTML and size provenance are retained.
Naivas uses `https://www.naivas.online/search?term=milk` in headless Firefox,
with its default Nairobi delivery area. Only the first page (12 candidates in the
live milk check) is scraped. Selling prices exclude crossed-out prices, explicit
Ltr/Ml/Gm title sizes are normalized, and ambiguous ranges or bundles remain
unknown. An enabled Add to Cart button indicates storefront availability; actual
stock may differ at the selected delivery store. Blank or blocked pages are errors.
Carrefour uses its default delivery area and the existing product-card parser.
Store searches may return broad candidates; users confirm equivalence themselves.

Each store cell has independent selection, blue banner, editable whole-pack count,
and row cost. Totals sum selected rows using Decimal arithmetic. Incomplete baskets
are labelled as selected subtotals. Retry clears only that store's selection;
remove and clear prune both stores, including late results. State resets on reload.

## Browser setup

```sh
cd priv/carrefour_browser
npm ci
env PLAYWRIGHT_BROWSERS_PATH=0 npm run install-browser -- --no-shell
```

Node must be available on the Phoenix server's PATH. Browser subprocesses do not
receive OPENAI_API_KEY or ANTHROPIC_API_KEY. Searches have a 45-second deadline and
a supervised FIFO queue per store. Each queue runs one browser lookup at a time;
additional requests wait instead of failing with browser_busy. Jobs have a
60-second execution cap once started; waiting time is separate. Caller cancellation
removes queued work and stops an active worker; worker failures release the queue. All three stores can run concurrently. The browser
is always headless; there is no visible-browser fallback. Optional
DEAL_AGENT_BROWSER_ENGINE overrides the store's default engine (`firefox` or `chromium`).
DEAL_AGENT_BROWSER_CHANNEL chooses another installed Chromium browser channel;
DEAL_AGENT_BROWSER_HTTP1=1 uses HTTP/1.1 without disabling TLS validation.

## Live verification (8 October 2026)

Quickmart milk scraping succeeded in headless Chromium. Carrefour milk scraping
succeeded in headless Firefox and its existing parser returned 60 products with
Decimal prices and normalized sizes. Firefox is now Carrefour's default engine.
The first page had no parsed 2-litre packs; smaller compatible packs can still
cover a 2-litre request through the selection flow. Carrefour's earlier headless
Chromium HTTP/2 navigation failed, and its HTTP/1.1 attempt timed out. Retrieval
failures remain errors rather than empty/missing items or fixture prices.

## Interpretation failures

OpenAI closed-connection errors receive at most one retry. BeamAgent's reply/tool
callback is wrapped by CheckedClient, which preserves provider failures without
crashing the runner. HTTP quota, credentials, model and service errors are shown
as specific messages rather than asking users to rephrase a valid request.
If transport still fails, a conservative local parser accepts a single explicit
quantity/unit request such as `2 litres of milk`. It preserves qualifiers, rejects
multiple items, and uses the same IntentConverter and supermarket search flow.
It does not bypass quota or authentication errors or fabricate search results.

## Unspecified quantities

A request without an amount retains `quantity_unspecified: true`. The model is
instructed to return null for quantity and unit rather than inventing an amount.
The UI labels the quantity as unspecified. Selecting an available product starts
at one pack, with an explicit reminder and editable pack count. Explicit amounts
continue to use compatible size conversion and rounding. Multi-item prose is interpreted in one BeamAgent run using `capture_intent` with
`add_items`. The items array preserves order and compound names, carries quantity
and unit separately for each item, and allows unspecified quantities. Batches of
1–30 items are validated atomically before list mutation. Each row then searches
all stores through their separate browser queues. Single-item and existing list
commands retain their original contracts. Transport fallback stays conservative:
ambiguous multi-item prose is not guessed locally.
