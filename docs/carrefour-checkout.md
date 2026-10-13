# Carrefour cart preparation

Shop now is enabled only after every shopping-list row has a Carrefour selection.
CartPlan freezes those choices, validates Carrefour URLs, and combines repeated
SKUs into an exact whole-pack quantity. Each product is capped at 50 packs.

CartJobs owns a separate Playwright Firefox process, with a fresh guest session.
The cart browser is visible on the local Phoenix server's desktop so the user can
continue in the same session. This initial implementation requires a desktop;
it is not a remote/headless-server checkout integration. A generic cart link in
another browser would lose this guest session, so Show Carrefour window brings
forward the existing browser instead.

The runner opens each exact selected SKU page, checks its current selling price,
adds only that product, and waits for each quantity acknowledgement before the
next mutation. It then opens the cart and checks all SKU identities and quantities.
It never clicks Checkout, places an order, signs in, or handles payment information.
The user reviews actual prices, fees, delivery details and payment on Carrefour.

Notyf provides persistent, dismissible in-app alerts. A ready alert requires cart
verification and an enabled Carrefour checkout button. If the cart is filled but
checkout is disabled (for example, below the minimum order), the alert requests
review rather than saying payment is ready. A price change, missing SKU, failed
quantity acknowledgement or connection failure stops preparation and shows a
failure message; a partial cart stays open for manual review. No automatic add
retry or replacement is attempted.

There is one open cart per LiveView process and at most three local cart browsers.
Preparation has a four-minute deadline; browser sessions expire after 30 minutes.
Closing the cart window frees the slot. Browser cookies remain only in the temporary
browser context and are not exposed to the app, persisted, or transferred. OpenAI
and Anthropic keys are removed from the browser subprocess environment.

Alerts require the app tab to remain open. Shopping state and cart job controls are
currently session-local and reset on reload. Later edits to the list or pack counts
do not change a cart already being prepared: close it and prepare a new snapshot.

Setup: run `npm ci --prefix assets` for Notyf, install the existing Playwright
Firefox runtime, then `mix assets.build`. External email/SMS notifications and
Quickmart/Naivas cart preparation are not part of this first increment.
