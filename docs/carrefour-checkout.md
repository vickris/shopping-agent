# Supermarket cart preparation

Shop now is enabled after at least one shopping-list row has a selection for that store. Unselected rows are skipped and only selected costs enter the cart estimate.
CartPlan freezes those choices, validates store-specific URLs, and combines repeated
SKUs into an exact whole-pack quantity. Each product is capped at 50 packs.

CartJobs owns a separate Playwright browser process (Firefox for Carrefour/Naivas, Chromium for Quickmart), with a fresh guest session.
The cart browser is visible on the local Phoenix server's desktop so the user can
continue in the same session. This initial implementation requires a desktop;
it is not a remote/headless-server checkout integration. A generic cart link in
another browser would lose this guest session, so Show store window brings
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

There is one open cart per store per LiveView process and at most three local cart browsers.
Preparation has a four-minute deadline; browser sessions expire after 30 minutes.
Closing the cart window frees the slot. Browser cookies remain only in the temporary
browser context and are not exposed to the app, persisted, or transferred. OpenAI
and Anthropic keys are removed from the browser subprocess environment.

Alerts require the app tab to remain open. Shopping state and cart job controls are
currently session-local and reset on reload. Later edits to the list or pack counts
do not change a cart already being prepared: close it and prepare a new snapshot.

Setup: run `npm ci --prefix assets` for Notyf, install the existing Playwright
Firefox and Chromium runtimes, then `mix assets.build`. Alerts are in-app only.

Quickmart uses the same Ruaka branch (store 1) as search. Before adding products,
it pauses for the user to enter their delivery location in the store window.
Continue resumes the same guest session and rechecks the location; repeated clicks
cannot replay basket additions. The four-minute preparation timer pauses while
waiting for input; the 30-minute session expiry still applies. Missing products,
changed prices or an unexpected branch stop the run without substitution.

Naivas fills a guest cart and verifies the saved SKU counts and line totals after
reloading the cart. Its Login to Proceed step remains for the user. Quickmart and
Naivas emit a verified cart-filled alert with a reminder to review delivery, sign
in if required and pay in the existing browser window. Neither runner enters
credentials or submits checkout. Store changes can require selector updates;
unverified/partial carts are reported as failures.


Cart preparation starts as a guest without an app-enforced sign-in prerequisite.
The store can still require login at checkout. The earlier experimental account
sign-in/phone confirmation hooks are not called by the cart runner.

Delivery-aware search remains separate from cart preparation: current searches
still use the configured/default areas described in the comparison UI. Changing
a cart's delivery address does not retroactively validate earlier search prices.
A Syokimau investigation found Quickmart's nearby branch selector lists Diamond
Biz and Highway–Mlolongo. Nearby listing is not a delivery guarantee. Each store's
selected delivery location must be carried into search and cart sessions before
we can mark its comparison column as confirmed for the user's delivery area.
