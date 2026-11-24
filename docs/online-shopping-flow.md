# Online shopping flow

## Product direction

Keep the existing chat and comparison table. Do not add a permanent store-status
banner, a new supermarket picker, or agent/tool controls. A user can ask:

> I want to shop for milk and ice and water. Compare Naivas and Carrefour.

The existing intent-capture parser extracts items and supermarket preferences.
Only the chosen stores appear in the comparison and receive item searches.
Omitting stores retains the current choice; initially all four stores are selected.
“Compare Quickmart” searches the existing list there without adding rows.
“Compare all supermarkets” restores the four columns. Asking which supermarkets
are available produces a chat reply rather than another permanent UI panel.

Existing homepage location setup is retained. Location browsers still initialize
through that workflow; an unselected store's confirmation does not trigger item
searches. Store choice is currently local to this LiveView, not durable across
refreshes. An active cart must be closed before hiding its store.

## Desired deployed experience

1. Open the HTTPS app, allow location access or supply an area.
2. Describe the shopping list and optionally name supermarkets in chat.
3. Receive results progressively; select products and review pack totals.
4. Show missing items and partial subtotals explicitly. Compare equivalent
   baskets before declaring a cheapest option; delivery fees need store confirmation.
5. Shop now snapshots the selected products for one supermarket and prepares
   its cart. Price or stock changes require review rather than silent substitutions.
6. Notify the shopper in-app when the cart is verified and ready for review.
7. Review and pay opens an isolated interactive supermarket session online.
   The shopper handles required login, exact-address confirmation, OTP and payment.

Durable guest identity, saved lists, checkout jobs surviving LiveView disconnects,
owner-authorized viewer access and session expiry are prerequisites for step 7.
These are planned, not implemented by the store-choice change. A supermarket
checkout URL alone cannot transfer a server browser's guest basket. Foodplus
checkout remains unavailable while its website reports maintenance.

## Remote browser decision: evaluate before implementing

Research checked 28 October 2026. No provider account, paid plan or checkout
integration has been created. All compatibility claims below need an end-to-end
test against the actual supermarkets, including requests from cloud IP addresses.

### Browserless: first managed-service candidate

Its documentation lists native Playwright Firefox and Chromium endpoints. Its
Live URL feature provides an interactive HTTPS viewer and can be embedded in an
application. However, documented Live URL creation uses CDP/Chrome connections.
Firefox automation support does **not** establish Firefox interactive-handoff
support. Prove that combination before choosing it for Carrefour or Naivas.

The pricing page currently lists a two-minute free-session limit and a
15-minute Prototyping-session limit. Checkout session lifetime must cover the
shopper's interaction; link validity alone does not keep the browser alive.

Sources:
- https://docs.browserless.io/overview/connection-urls
- https://docs.browserless.io/baas/monitor-sessions/embedding-live-url
- https://docs.browserless.io/baas/monitor-sessions/hybrid-automation
- https://www.browserless.io/pricing

### Browserbase: alternative requiring a mobile-input test

Its Live View supports embedded interaction, but the documentation says mobile
keyboards are not officially supported and describes custom keyboard forwarding.
That is a material implementation requirement for phone checkout. The existing
Firefox adapters also need compatibility verification before selecting this service.

Source: https://docs.browserbase.com/platform/browser/observability/session-live-view

### Self-hosted browser workers: fallback preserving the existing engines

A separate worker service could run the existing Firefox/Chromium engines in
isolated sessions and expose a browser viewer through noVNC/websockify. This is
a proposed architecture, not a tested checkout solution. We would own container
isolation, authenticated viewer routing, TLS, cleanup, resource limits, updates
and mobile-input verification. Keep it separate from the Phoenix application.

Sources:
- https://github.com/novnc/noVNC
- https://github.com/novnc/websockify

## Decision gates

Start with one Carrefour compatibility prototype, without placing an order:

- Resolve the supplied location and preserve it through search and cart preparation.
- Add selected products and verify SKU, quantity and current price.
- Open the same verified session on a phone; verify typing, scrolling and popups.
- Reach checkout review, stopping before payment or order submission.
- Verify disconnect/reconnect, session expiry and isolation between two shoppers.
- Confirm an adequate lifetime and acceptable usage cost before buying a plan.

Prefer managed infrastructure if the whole prototype passes. Otherwise assess
the self-hosted worker approach; do not change working store engines just to
fit a provider or promise Firefox handoff based on automation support alone.

### Headless preparation and embedded checkout

The hosted configuration uses `REMOTE_CHECKOUT_ENABLED=true` and
`BROWSER_CHECKOUT_ENABLED=false`. Remote checkout takes precedence if both are
enabled. Preparation runs in the existing server-side headless delivery session;
it does not create an extension tab. The shopper explicitly opens the private
checkout view to review and pay inside the app.

Naivas requires a saved full delivery address, including required contact details,
before adding products. Coordinates or a comparison area alone do not satisfy
this requirement. Use **Open delivery address setup** in location settings to
complete Naivas's form in the embedded store view, then **Confirm saved delivery
address** before preparing the cart. Catalogue comparison remains available.

Existing Render services must update these environment variables and deploy the
new version; changing the Blueprint does not update a running service by itself.

### Optional local Carrefour checkout window

Hosted checkout uses `REMOTE_CHECKOUT_ENABLED=true` and
`LOCAL_HELPER_ENABLED=false`. Shoppers do not install an extension or helper.
Clicking checkout opens the retained store session inside Shopping Agent.
This keeps its address, products and quantities together through payment.
The remote flow takes precedence over a stale helper setting.

The local helper remains available for desktop development when remote checkout
is disabled. See `priv/local_helper/README.md` for that optional setup.

### Naivas address confirmation inside the app

With remote checkout enabled, **Set Naivas delivery address** opens the store's
address form in the existing app view, including when geolocation is unavailable.
The shopper saves their address in Naivas and clicks **Confirm saved delivery
address**. Modern Naivas confirmation checks that the address survives navigation
before returning to comparison and refreshing products for the saved location.
An incomplete form or unsaved address does not count as confirmed. GPS sessions
can use this manual completion step; other stores retain automatic confirmation.

The local Carrefour helper reports the store's specific cart errors. Protocol
errors on page navigation can retry once; add-to-cart actions never retry after
an uncertain result. Progress shows item additions and cart readiness.

A saved address in a separate Naivas browser tab belongs to a different session
from hosted cart preparation. Save it using **Set Naivas delivery address** in
the app. Clicking **Prepare cart** before confirming the address opens that
form instead of a generic location error. After confirmation, unchanged selected
SKUs and pack counts are restored using fresh store results; changed prices or
unavailable products require a new selection. The current Naivas React cart is
filled and verified using the same storefront controls as the extension. Their
canonical source is `priv/carrefour_browser/storefront_steps.mjs`;
`mix extension.build` synchronizes the packaged extension copy.
