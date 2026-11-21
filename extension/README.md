# Shopping Agent browser checkout 0.4.0 (desktop Chrome / Edge)

This is a demo extension, not a Chrome Web Store publication. Install it once per
shopper's desktop browser. It does not work in mobile Chrome.

1. Download the ZIP from Shopping Agent, unzip it into a permanent folder.
2. Open `chrome://extensions` (or `edge://extensions`), enable Developer mode,
   choose **Load unpacked**, and select the folder containing `manifest.json`.
3. Return to Shopping Agent, select products and choose **Prepare cart**.
4. On first use, choose **Enable supermarket access** in the app. In the extension
   setup tab, choose **Enable background checkout** and grant access to that store.
   This returns you to Shopping Agent. Existing store permissions are reused.
5. Cart preparation runs automatically in an inactive supermarket tab. Stay on
   the shopping page to see progress. It first clears the **entire store cart**,
   including manually added items, then opens each selected product link once to
   add its requested quantity. There is no preflight product pass or repeat
   catalogue search. Prices/stock are checked while adding, then the completed
   cart is verified. A stock/price failure can leave an empty or partial cart.
6. If sign-in or delivery selection is needed, choose **Open supermarket** in the
   app, complete the store prompt normally, then **Resume preparation** in the app.
   The extension has no permission to access Google or payment sites.
7. A cart-ready notification appears in Shopping Agent. Choose **Open cart**,
   review products, fees and final total, then complete checkout/payment yourself.

There is no per-order extension review page. The toolbar icon still opens an
optional troubleshooting window, but ordinary preparation, progress, resume and
stop controls are available on the shopping page. First-time permissions and
occasional store authentication/delivery prompts still require user action.

If a store redirects, changes its markup, prices or branch, the transfer stops
and tells you why. If removal controls are unsupported, manually empty the cart
and resume; it does not add new products before confirming the old cart is empty.
Stock limits can still surface after Add; a partial cart is never marked verified.
After an interruption inspect the store cart before explicitly resuming. Resuming
continues the current step without clearing already-added products again. Sending
a new order supersedes the old transfer, closing an actively running helper first.
Stop transfer stops automation but does not delete the store cart.

Basket descriptions and progress are held in `chrome.storage.session`, expire
30 minutes after export and clear on browser restart. No persistent product
receipts are needed in fresh-cart mode; the old 0.1.3 receipts are removed on
update. Your normal store cookies remain in your browser; the extension does not
read or export cookies, passwords, tokens or payment data. No browser debugging
API, remote code, server callback or login-form injection is used. Google sign-in
is a normal interaction between you and the store/Google. Compatibility with a
retailer or identity provider is still subject to its rules.

For a local app test, run `BROWSER_CHECKOUT_ENABLED=true mix phx.server` on port
4000. Local desktop checkout remains the default without that flag.

Supported app origins: `https://deal-agent-beta.onrender.com` and
`http://localhost:4000`. If deploying to a different hostname, explicitly update
`APP_ORIGINS` in `policy.js`, and both `content_scripts.matches` and
`host_permissions` for the app in `manifest.json`, rebuild the ZIP, and reload the extension. Do not use wildcard
app origins. Store permissions are optional and requested per supermarket.

Supported cart adapters: Carrefour, Quickmart, Naivas. Foodplus remains outside
the automated checkout adapters. Store order totals, fees, stock and delivery
eligibility must be reviewed before payment. Automated fixture tests exercise
fresh-cart replacement in all three stores; real-store behavior can still vary.

For an update, replace all files in the original unpacked extension folder and
click Reload on its chrome://extensions card. Check version 0.4.0; do not install
a second copy. Refresh Shopping Agent and send a new order after updating.
The updated app sends protocol version 3 so older extensions reject fresh-cart
orders instead of retaining the old manual review flow. Version 0.4.0 also accepts
versions 1 and 2 from previously deployed apps while you roll out the update.
Carrefour offer/seller parameters are preserved in product links;
credential/redirect query parameters remain unsupported. General-catalogue
comparisons require confirming delivery and current prices in the store.

Checkout errors include the background worker version and validator revision.
Version 0.4.0 reports `offer-links-v2`; an unknown validator can indicate mixed
extension files. The reported Carrefour milk (81030) and water (17396) offer links
are regression-tested together.

Version 0.4.0 keeps stage messages accurate between navigations. An inactive
cart tab from the previous transfer is reused in the same browser window;
active tabs, payment/checkout pages and unrelated store tabs are left alone.
The Del Monte (38605) and toothpaste (120137) two-product regression checks
that every old line is removed before either product is added, and that only
one ready event is sent after both products have been verified.

Naivas supports the current React cart drawer as well as the earlier Livewire
layout. The React adapter verifies product image IDs, unit prices and quantities,
clears the drawer with the store confirmation, and verifies the final basket.
Naivas requires a saved delivery address; its default “Nairobi, Kenya” label is
not treated as confirmation. Complete its address/contact form once, then resume.
Quickmart uses the direct product form and enforces its seller branch.
