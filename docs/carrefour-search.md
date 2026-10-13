> The app now uses headless browser scraping for both stores. See
> [current supermarket search documentation](supermarket-search.md) for transport,
> branch context and live verification limits. HTTP details below describe the
> optional HTTP client and earlier implementation.

# Carrefour product search

```elixir
alias DealAgent.Shopping.Item
alias DealAgent.Supermarkets.Carrefour

Carrefour.search(Item.new("milk", quantity: "2", unit: :litre))
```

`Carrefour.search/2` still implements the supermarket behaviour and returns
`{:ok, %SearchResult{}}` or `{:error, reason}`. The existing injectable `:client`
option and clients implementing `search/1` continue to work.

The default client requests
`https://www.carrefour.ke/mafken/en/search?keyword=...` using Req, then parses
product cards with Floki. Blank pages, transport failures and HTTP 403 trigger
an isolated Playwright browser lookup, using the same parser. HTTP 429 is not retried. The parser uses the card markup inspected on the live
Kenya site on 8 October 2026. This is an HTML integration, not a documented store
API; changes to the site's markup can require parser updates.

## Product semantics

- Price is the displayed selling price for one pack, in KES, as a Decimal.
  Former prices and coupon discounts are not used.
- Quantity describes total contents of that pack, in its labelled unit.
  `250ml x 6 Pieces` becomes 1500 millilitres; `30 Pieces` becomes 30 each.
  The price remains the price of the whole pack.
- Unit spelling is normalized; amounts are never converted through floats.
- Missing or ambiguous size labels (including mixed bundles) produce nil quantity
  and unit. Future matching must explicitly handle these products; do not assume
  they are comparable by weight or volume.
- Brand is nil when the card does not supply it. No brand or size is inferred
  from the title.
- Availability reflects the presence of an enabled Add to cart button.
- `Product.raw` retains the parsed client fields plus the source card HTML,
  original size label, and known/unknown size status.

## Scope and errors

Only the initial results page is fetched. There is no pagination, product
automatic product matching yet. The chat compare action refreshes searches.
Prices and availability reflect the website's default delivery area; no branch
or shopper delivery location is selected.

An explicit no-results page returns an empty products list. HTTP errors,
timeouts, malformed cards, and unexpected pages return errors. They must not be
interpreted as missing shopping-list items.

Requests use a 5-second connection timeout and 15-second receive timeout, without
automatic retries. Callers may pass `:request_options` through Carrefour.search/2
for Req transport options; tests use a Plug stub to exercise the HTTP boundary.
The usual production call needs no options.

## Verification

Offline tests cover the observed card structure, encoded queries, size labels,
multipacks, unknown sizes, decimal prices, former prices, availability,
deduplication, no results, invalid cards, HTTP status errors and transport errors.

Live browser retrieval was verified on 8 October 2026: the milk search returned
60 products with normalized prices and sizes. Direct HTTP returned blank HTML.
On macOS, the runtime defaults to installed Google Chrome in visible mode,
because headless Chrome failed against the store in this environment. A temporary
Chrome window opens during a lookup and closes afterward. Other platforms default
to bundled headless Chromium and need their own live verification.

Install the runtime once:

```sh
cd priv/carrefour_browser
npm ci
env PLAYWRIGHT_BROWSERS_PATH=0 npm run install-browser -- --no-shell
```

Node.js must be on the server's PATH. macOS also needs Google Chrome installed.
`CARREFOUR_BROWSER_CHANNEL` and `CARREFOUR_BROWSER_HEADLESS` override the defaults.
Browser searches have a 45-second overall deadline and allow one local lookup at
a time; concurrent lookups report busy and can be retried. Browser subprocesses
receive neither OPENAI_API_KEY nor ANTHROPIC_API_KEY. Browser dependency failures
and timeouts remain errors, never fixture prices or missing-item claims.

## Chat-to-search flow

At `/`, submit `2 litres of milk` in the chat. The OpenAI-powered shopping agent
captures an add-item intent (`milk`, quantity 2, unit litre). The LiveView adds it
to the shopping list and starts Carrefour.search/2 asynchronously. Each requested
item has a row in the supermarket table, with Carrefour as the only store column.
Manual additions use the same search flow.

The column displays candidate product links, per-pack KES prices, total pack
contents, and availability. It also handles loading, explicit empty results,
unreadable store responses, and other search failures, with a Search again button.
Removing or clearing an item discards its results, including late responses.
The chat command `compare` refreshes searches for the current list.

Users confirm an equivalent product with Select product. A blue banner shows the
selection, whole-pack count and row cost. Compatible volume and mass units are
converted with Decimal arithmetic and pack counts round up; Each means a count of
listed packs. Pack counts can be edited or selections cleared. Unknown-size and
incompatible products cannot be selected for volume or mass requests.

The Carrefour total sums selected row costs and is marked incomplete until every
row has a selection. Refreshing a search clears its selection to avoid retaining
stale prices. Selections are held in LiveView state and reset when the page reloads.
No cheapest-store claim is produced at this stage.

The server reads OPENAI_API_KEY at startup. Export it in the terminal that starts
`mix phx.server`; an export in another terminal or after startup will not update
an existing server. Restart the server after setting the variable. The key is not
sent to the browser or checked into the project. The OpenAI adapter performs one
model call per interpretation and completes the agent locally after intent capture.
