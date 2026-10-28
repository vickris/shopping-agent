# Supermarket cart preparation

Shop now is enabled after at least one shopping-list row has a selection for that store. Unselected rows are skipped and only selected costs enter the cart estimate.
CartPlan freezes those choices, validates store-specific URLs, and combines repeated
SKUs into an exact whole-pack quantity. Each product is capped at 50 packs.

DeliverySessions reuses the location-confirmed search browser for cart preparation
(Firefox for Carrefour/Naivas, Chromium for Quickmart). Cookies stay in the same
temporary browser context; no new guest session replaces the confirmed session.
The cart browser is visible on the local Phoenix server's desktop so the user can
continue in the same session. This initial implementation requires a desktop;
it is not a remote/headless-server checkout integration. A generic cart link in
another browser would lose this guest session, so Show store window brings
forward the existing browser instead.

The runner opens each exact selected SKU page, checks its current selling price,
adds only that product, and waits for each quantity acknowledgement before the
next mutation. It then opens the cart and checks all SKU identities and quantities. Carrefour
verification supports its current expanded quantity widgets as well as legacy
quantity dropdowns. Current cart rows must also have the expected line totals;
recommendation cards are excluded. A failed verification is reported as a cart
mismatch, separately from navigation failures and control-loading timeouts.
It never clicks Checkout, places an order, signs in, or handles payment information.
The user reviews actual prices, fees, delivery details and payment on Carrefour.

Notyf provides persistent, dismissible in-app alerts. A ready alert requires cart
verification and an enabled Carrefour checkout button. If the cart is filled but
checkout is disabled (for example, below the minimum order), the alert requests
review rather than saying payment is ready. A price change, missing SKU, failed
quantity acknowledgement or connection failure stops preparation and shows a
failure message; a partial cart stays open for manual review. No automatic add
retry or replacement is attempted.

There is one delivery session per store per LiveView process and at most six local
delivery browsers. A prepared cart reserves its session for the checkout handoff.
Preparation has a four-minute deadline; browser sessions expire after 30 minutes.
Closing the cart window frees the slot. Browser cookies remain only in the temporary
browser context and are not exposed to the app, persisted, or transferred. OpenAI
and Anthropic keys are removed from the browser subprocess environment.

Alerts require the app tab to remain open. Shopping state and cart job controls are
currently session-local and reset on reload. Later edits to the list or pack counts
do not change a cart already being prepared: close it and prepare a new snapshot.

Setup: run `npm ci --prefix assets` for Notyf, install the existing Playwright
Firefox and Chromium runtimes, then `mix assets.build`. Alerts are in-app only.

Quickmart uses the branch selected in the confirmed delivery session. Before
adding products, it rechecks the location and branch. Missing products, changed
prices or an unexpected branch stop the run without substitution.

Naivas fills a guest cart and verifies the saved SKU counts and line totals after
reloading the cart. Its Login to Proceed step remains for the user. Quickmart and
Naivas emit a verified cart-filled alert with a reminder to review delivery, sign
in if required and pay in the existing browser window. Neither runner enters
credentials or submits checkout. Store changes can require selector updates;
unverified/partial carts are reported as failures.


Cart preparation starts as a guest without an app-enforced sign-in prerequisite.
The store can still require login at checkout. The earlier experimental account
sign-in/phone confirmation hooks are not called by the cart runner.

Search and cart preparation share each store's confirmed delivery session. A
changed or expired location clears its old prices and selections. Naivas alone
allows the shopper to use a supplied area when its map will not update; this is
marked delivery unverified, and the final address and coverage must be checked
in Naivas checkout. See README.md for the delivery setup flow.

If a previous attempt failed after adding products, review that cart before
starting another preparation. The runner does not automatically replay additions.
To load updated browser code, close the existing delivery session and reopen it.

Browser regression checks:
`node --test priv/carrefour_browser/carrefour_cart.test.mjs priv/carrefour_browser/cart_errors.test.mjs`.
