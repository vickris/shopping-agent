# Shopping Agent browser checkout 0.1.1 (desktop Chrome / Edge)

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
6. Return to the extension tab and choose **Location confirmed — build basket**.
   Keep the helper tab open while it builds. It checks prices and sets selected
   products to the requested pack counts. It does not empty your existing cart.
7. Review all cart items, delivery fees and the final total on the supermarket
   website. Submit checkout and payment yourself. The extension never does this.

If a store redirects, changes its markup, prices or branch, the transfer stops
and tells you to review it. After an interruption inspect the store cart before
explicitly resuming. Quantity controls are read before changing them; the helper
never blindly repeats Add to cart after a failed response. No background retries.
Clear / stop transfer closes the helper tab only if a transfer is actively
running, to stop further input. Existing cart contents are not deleted.

Basket descriptions and progress are held in `chrome.storage.session`, not synced
or saved to disk by this extension. Instructions expire 30 minutes after export
and clear on browser restart. Your normal store cookies remain in your browser;
the extension does not read or export cookies, passwords, tokens or payment data.
No browser debugging API, remote code, server callback or login-form injection is
used. Google sign-in is a normal interaction between you and the store/Google.
Compatibility with a retailer or identity provider is still subject to its rules.

For a local app test, run `BROWSER_CHECKOUT_ENABLED=true mix phx.server` on port
4000. Local desktop checkout remains the default without that flag.

Supported app origins: `https://deal-agent-beta.onrender.com` and
`http://localhost:4000`. If deploying to a different hostname, explicitly update
`APP_ORIGINS` in `policy.js`, and both `content_scripts.matches` and
`host_permissions` for the app in `manifest.json`, rebuild the ZIP, and reload the extension. Do not use wildcard
app origins. Store permissions are optional and requested per supermarket.

Supported cart adapters: Carrefour, Quickmart, Naivas. Foodplus remains outside
the automated checkout adapters. Existing unrelated basket items are kept.
Only compared prices for selected items are checked; store order totals, fees,
stock and delivery eligibility must be reviewed before payment.

For an update, replace files in the original unpacked extension folder and click
Reload on its chrome://extensions card. Check version 0.1.1; do not install a
second copy. Carrefour offer/seller parameters are preserved in product links;
credential/redirect query parameters remain unsupported. General-catalogue
comparisons require confirming delivery and current prices in the store.
