# Shopping Agent browser checkout 0.2.0 (desktop Chrome / Edge)

This is a demo extension, not a Chrome Web Store publication. Install it once per
shopper's desktop browser. It does not work in mobile Chrome.

1. Download the ZIP from Shopping Agent, unzip it into a permanent folder.
2. Open `chrome://extensions` (or `edge://extensions`), enable Developer mode,
   choose **Load unpacked**, and select the folder containing `manifest.json`.
3. Return to Shopping Agent. Select products and choose **Checkout in my browser**.
4. Review the basket in the extension tab. **Open supermarket & sign in** asks
   for permission to access only that supermarket, then opens a helper store tab.
5. Sign in normally (including Google if offered) and confirm your delivery
   address. The extension has no permission to access Google or payment sites.
6. Return to the extension tab and choose **Replace cart & build this order**.
   This replaces the **entire supermarket cart**, including manually added items.
   It checks selected prices/visible stock limits, confirms the old cart is empty,
   adds exactly the selected quantities, then verifies all products and prices.
   Keep the helper tab open while it builds. Progress/errors also appear in the
   originating app tab after deploying the updated app assets.
7. Review all cart items, delivery fees and the final total on the supermarket
   website. Submit checkout and payment yourself. The extension never does this.

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
click Reload on its chrome://extensions card. Check version 0.2.0; do not install
a second copy. Refresh Shopping Agent and send a new order after updating.
The updated app sends protocol version 2 so older extensions reject fresh-cart
orders instead of silently preserving old items. Version 0.2.0 also accepts
version 1 from the previously deployed app while you roll out the update.
Carrefour offer/seller parameters are preserved in product links;
credential/redirect query parameters remain unsupported. General-catalogue
comparisons require confirming delivery and current prices in the store.

Checkout errors include the background worker version and validator revision.
Version 0.2.0 reports `offer-links-v2`; an unknown validator can indicate mixed
extension files. The reported Carrefour milk (81030) and water (17396) offer links
are regression-tested together.
