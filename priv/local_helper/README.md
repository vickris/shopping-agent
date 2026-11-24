# Local Carrefour helper (desktop demo)

Carrefour preparation runs in a fresh headless Firefox session on the shopper's
computer. Clicking **Open cart & checkout** restores that guest session into a
separate visible Firefox window and verifies the cart before handing it over.
No products are added again during handoff. The user confirms their delivery
address, fees, prices and payment in Carrefour. This is not a tab in existing
Chrome, and does not use Chrome's existing Carrefour account or cart.

## Install on macOS or Linux

Requires Node.js 22 or newer on each shopper's computer. Download and unzip the
local helper archive, then open a terminal in its extracted root directory.
These commands also work from a project checkout.

1. Run `npm ci --prefix priv/carrefour_browser` from the project root.
2. Run `PLAYWRIGHT_BROWSERS_PATH=0 npx --prefix priv/carrefour_browser playwright install firefox`.
3. Use **Load unpacked** on `chrome://extensions` or `edge://extensions` and
   select the extracted `extension` directory. Version 0.5.0 or later is required.
4. Copy that extension's ID from its extensions card and run:
   `node priv/local_helper/install.mjs EXTENSION_ID chrome`
   (replace `chrome` with `edge` for Edge).
5. Reload the extension and refresh Shopping Agent. The helper starts automatically
   when you click **Prepare cart**. No daemon or manual browser launch is needed.

Keep the project at its installed path. Rerun the installer after moving it or
changing the extension ID. Native messaging explicitly allows only the installed
extension ID; there is no localhost HTTP service or pairing token.

## App configuration and use

Set `LOCAL_HELPER_ENABLED=true` on the app and restart/deploy it. This takes
precedence for Carrefour only; `REMOTE_CHECKOUT_ENABLED=true` can remain enabled
for other stores. The Render Blueprint includes both settings. Existing services
must update their environment settings explicitly.

Prepare the cart, keep Shopping Agent open, then click **Open cart & checkout**.
Nothing opens during preparation. If Carrefour requires a location, login, stock
or price review, the helper stops and offers **Open supermarket** for inspection.
It never silently resumes uncertain additions. Stop the attempt before preparing
another cart. A new attempt uses a fresh guest cart. Coordinates from the hosted
search browser are not copied locally; Carrefour's local prices are checked
against the selected prices and the address must be confirmed before paying.

Cookies, local/session storage and IndexedDB remain in local browser memory;
they are never sent to the hosted app or written to a persistent profile. Only
basket descriptions and progress cross the extension bridge. No orders, login
forms or payment forms are submitted automatically. Sessions expire after 30
minutes; preparation is limited to four minutes. Stopping or disconnecting the
extension destroys the session. A browser restart cannot recover a prepared cart.

To uninstall, remove `io.deal_agent.cart_helper.json` from the browser's
`NativeMessagingHosts` directory and remove `~/.local/share/deal-agent/cart-helper`.
