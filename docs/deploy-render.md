# Deploy the friends beta on Render

This deployment supports chat, supermarket searches, product selection, totals,
and desktop browser-extension checkout for Carrefour, Quickmart and Naivas.
Foodplus checkout remains unsupported by its adapter. Shoppers build the basket
in their own Chrome/Edge session, sign in normally on the store website, and
review and pay there. The local desktop flow remains available.

## Create the deployment

1. Create an account at https://dashboard.render.com/register using GitHub.
2. Push the deployment commit to `vickris/shopping-agent` after authorizing the
   push. In Render choose **New → Blueprint** and connect that repository, granting
   access only to the repository needed. Select the branch containing `render.yaml`.
3. Review the resources before creating them. The Blueprint requests one paid
   `2c-4g` web service (2 CPU / 4 GB RAM) in Frankfurt and a paid
   `0.1c-256mb` PostgreSQL database with 1 GB of storage. Check Render's
   displayed price for both resources and database storage before creating them.
   A Hobby workspace can use paid compute; a paid workspace subscription is not
   required for this beta.
4. Enter `OPENROUTER_API_KEY` and `SECRET_KEY_BASE` directly in Render's secret
   environment fields. Generate the latter locally with `mix phx.gen.secret`
   (at least 64 bytes); do not use a shorter automatically generated value.
   The Blueprint sets `LLM_PROVIDER=openrouter` and uses
   `openai/gpt-4.1-mini`; change the model only to one that supports the
   intent-capture tool call. Do not paste API keys into chat, source files or
   build arguments.
5. Create the Blueprint. The Docker build compiles the Phoenix release, installs
   the matching Firefox and Chromium binaries and checks that both launch as the
   unprivileged runtime user. The pre-deploy command runs database migrations.
6. When healthy, open the HTTPS service URL and share it with testers. The
   shopping page is public and does not require a username or password.

Render supplies the public hostname automatically. `/health` is public and checks
database connectivity; the shopping interface is public.

## Exact dashboard settings

Use **New → Blueprint** with `vickris/shopping-agent`, branch `main`, and
Blueprint path `render.yaml`. This is the preferred path because it wires the
internal database URL and migration command automatically.
Push the local commits first so Render builds the current UI and Foodplus fix.
If a previous service used the native Elixir runtime, create this Docker service
alongside it and verify it before removing the old service.

If creating the resources manually, use these settings:

- PostgreSQL: `deal-agent-beta-db`, Frankfurt, `0.1c-256mb` compute, 1 GB storage.
  Database name `deal_agent`, user `deal_agent`. Keep external access disabled.
- Web service: `deal-agent-beta`, repository `vickris/shopping-agent`, branch
  `main`, runtime **Docker**, region **Frankfurt**, one `2c-4g` instance.
- Root directory: leave blank. Dockerfile path: `./Dockerfile`. Docker build
  context: repository root (`.`).
- Docker Command: leave blank to use the image's `/app/bin/server` command.
  Do not enter native Elixir build or start commands.
- Pre-deploy command: `/app/bin/migrate`. Health check path: `/health`.
  Automatic deploys: off. No persistent disk is needed on the web service.
- Environment: use all values in `render.yaml`. For manual creation, supply the
  database's **internal** URL as `DATABASE_URL`, generate `SECRET_KEY_BASE` with
  `mix phx.gen.secret` (minimum 64 bytes). Put the
  `OPENROUTER_API_KEY` directly in Render's Environment settings.

For the desktop extension flow, set `BROWSER_CHECKOUT_ENABLED=true`,
`REMOTE_CHECKOUT_ENABLED=false`, and `LOCAL_BROWSER_ENABLED=false`. All three
settings are in the Blueprint; update them manually for an existing deployment.
Server browsers still perform product searches, but do not build checkout carts
in this mode. The selected basket is exported to the shopper's extension.
The Docker image enables the Phoenix server and installs browser binaries; do not override
`PLAYWRIGHT_BROWSERS_PATH` or add a single-browser engine override.

Render sets `RENDER_EXTERNAL_HOSTNAME`, which the app already uses. Leave
`PHX_HOST` unset for an `onrender.com` domain. Browser geolocation must be used
through the HTTPS URL. Set `PHX_HOST` to your hostname if adding a custom domain.

## Fix an existing short secret and password-gated deployment

In the web service's Environment settings, replace `SECRET_KEY_BASE` with the
output of `mix phx.gen.secret` run locally. Keep the value secret and do not
regenerate it on each start. Delete legacy `BETA_USERNAME` and `BETA_PASSWORD`
variables. Deploy the latest code; the public router no longer uses the beta gate.
Changing the cookie secret invalidates existing sessions, so reload the app after
deployment. A short secret is rejected at startup with an explicit message.

## Verify before inviting friends

If an initial attempt used Render's native **Elixir** runtime, create a new
**Docker** web service from this repository or use **New → Blueprint**. Do not
reuse the native service's build/start commands: the Dockerfile owns those steps
and installs the required browser engines and system libraries. The native
Elixir service can be removed once the Docker service has been verified.

- Confirm `/health` returns `{"status":"ok"}`.
- Open the homepage without credentials and verify that it loads normally.
- Allow browser location access, then search for milk and select a product.
- Check results and totals from each available supermarket. A successful image
  build proves the browser engines launch, but store access from Render's network
  still needs this live check; retailer blocking can differ from a local machine.
- On desktop Chrome/Edge, install the checkout extension using the download link
  beneath the store total. Return to Shopping Agent, select products and choose
  Checkout in my browser. Follow the extension review, sign-in, location and cart
  steps. Review quantities and the final total on the store website. Do not place
  a real order just to test deployment. The extension is not supported on phones;
  product comparison remains available there.

## Beta limits and operations

The 0.1 CPU option may refer to the database, which is separate from the web
service. Check the resource label in Render. A free web service has only 512 MB
RAM; running Phoenix plus multiple supermarket browsers there is not a validated
configuration. Choosing smaller compute does not cause a missing Mix task during
the build. This Blueprint retains the proposed 4 GB web service; review the
selected plan and its cost before applying it.

This runs one instance with Erlang distribution disabled. Do not scale to multiple
instances until session routing and shared state are implemented. The limit of
eight browser sessions is roughly two simultaneous visitors using all four
supermarkets, not a load-tested capacity guarantee. Measure memory and search
latency before increasing it. Closing a shopper connection releases its sessions.

Shopping lists and selections are not durable accounts: refreshes, disconnects
and deployments can lose the current comparison. Each shopper has separate
browser state, but visitors share the model API budget.
Set an appropriate provider budget for the public demo.

Automatic deploys are off to avoid interrupting active shoppers on every push.
Use Render's manual deploy action for subsequent releases. Inspect application
logs for errors without sharing API keys, passwords or store session data.

The native production release, authentication gate and browser engines have been
tested locally. A Linux Docker build must still complete on Render: this workspace
does not have a Docker engine installed.

References: [Blueprint specification](https://render.com/docs/blueprint-spec),
[compute plans](https://render.com/docs/compute-plans),
[pricing](https://render.com/pricing),
[Playwright browser installation](https://playwright.dev/docs/browsers).

## Browser checkout extension (preferred)

The Docker build packages `extension/` into
`/downloads/shopping-agent-extension.zip`. For local packaging, run
`mix extension.build` (also included in both asset build aliases). Download the
ZIP, extract it, open `chrome://extensions` or `edge://extensions`, enable
Developer mode and Load unpacked with the extracted folder. Return to the app after
installing; the extension connects to an already-open app tab. For a public non-developer install, publish through the browser's
extension store separately; no store publication has been performed.

The extension first shows the selected products and pack counts. The shopper
explicitly approves access to the selected supermarket, signs in normally and
confirms delivery, then chooses Build basket. Only then does the extension use
store cart controls. Selected prices are checked before adding products, selected
quantities are read before adjustment, and unrelated existing items are preserved.
The full cart may therefore cost more than the app's selected subtotal. The user
reviews all items, delivery fees and final totals before paying. The extension
never clicks checkout, payment or login controls.

Only basket descriptions are passed from the app. The extension does not read or
export cookies, passwords, login tokens or payment details. It has no Google,
payment-domain, cookie API, debugger or broad all-sites permissions. Retailer
permissions are optional and approved per store. Temporary basket/progress data
uses `chrome.storage.session` and expires after 30 minutes. Store authentication
and carts remain in the shopper's own browser account. Stop / clear transfer does
not empty the store cart. Closing an active helper tab stops further automation.

Google sign-in takes place in a normal browser tab without scripted interaction
or server-session transfer; identity providers and retailers can still impose
their own access rules. Changed markup, prices, redirects or branch mismatches
stop the transfer for user review. A transfer is never blindly retried after an
uncertain cart update. Live retailer and sign-in checks must be performed on the
installed browser before demoing; fixture tests do not certify live payments.

App origins are explicitly allowlisted in `extension/manifest.json` and
`extension/policy.js`. Both include the current Render URL and localhost:4000.
Update both, rebuild and reload if moving to a custom domain. Never wildcard
all app domains. See `extension/README.md` for installation and privacy details.

Tests: `node --test --test-concurrency=1 test/extension/*.test.mjs`.

## Private remote checkout (optional, disabled by default)

This older alternative uses `REMOTE_CHECKOUT_ENABLED=true` with
`BROWSER_CHECKOUT_ENABLED=false`. It can be incompatible with Google sign-in;
the browser-extension path above is preferred.

The viewer sends bounded clicks, keystrokes, scrolling and viewport images over
that shopper's existing LiveView connection. There is no public browser endpoint,
shareable cart URL or debugging port. Sessions remain owned by the LiveView PID;
other connections cannot request frames or send input even if they know a session
ID. The store browser closes on owner disconnect, explicit End private session,
request timeout or its existing 30-minute expiry. Back to comparison only hides
the viewer and preserves the reserved cart. Refreshing the app loses the session.

Browser state, frames and keyboard input are not written to recordings or the
database. Remote input and frame parameter keys are filtered from application
logs. Do not enable protocol tracing, Playwright debugging or session-recording
software for production checkout. Input is sent once; an uncertain input is not
replayed automatically. Check the store's order status before repeating payment.

The original cart session stays headless, so no VNC server, extra desktop process,
or OS packages beyond the existing Docker image are needed. HTTP and websocket
requests in remote-enabled contexts are restricted to HTTPS/WSS public hosts;
private, loopback and cloud metadata addresses are blocked by the browser routing
policy. The viewport refreshes at about one frame per second while visible and
active, and pauses after five minutes without input. This is an interactive image
viewer, not a full desktop: passkeys, native file dialogs, downloads and bank-app
handoffs are not supported. OTP text input, page dialogs, ordinary forms and
payment tabs have controls. Bank/provider restrictions can still prevent checkout
from a cloud browser; no live purchase or payment-provider certification is implied.

Remote browsing sends image data through Render, so measure outbound bandwidth
and browser memory during the demo. Existing browser caps still apply. Keep a
single web instance; do not scale horizontally without session routing.

Browser regressions: `node --test priv/carrefour_browser/remote_checkout.test.mjs`.

## Price comparison when delivery is unconfirmed

Delivery availability and price comparison are independent. Without a confirmed
location, searches use a temporary public/general catalogue and label its prices
as comparison-only. If a confirmed location-specific search fails, the app makes
one general-catalogue fallback attempt. If that request also fails, the store
error remains visible; the app does not fabricate prices or bypass store blocks.

A failed location lookup is not proof of a retailer's coverage policy. The UI
says no delivering store could be found and that delivery is unconfirmed. It does
not claim that a generic/reference branch serves the shopper. Comparison-only
prices have no confirmed delivery session ID, cannot be used for server cart
handoff, and do not export an unrelated branch ID to the checkout extension.
The shopper confirms the address and current prices in the native store session.

Extension 0.1.1 accepts Carrefour's commerce offer/seller query parameters while
retaining the retailer/product checks and refusing credential/redirect queries.
After updating, replace the files in the original unpacked extension folder and
click Reload on its chrome://extensions card. Verify version 0.1.1 and resend the
basket; do not install a second copy alongside the old extension.

Foodplus zero-price catalogue placeholders are excluded, rather than treated as
free items or causing the entire priced result list to fail. Malformed prices
and foreign links still fail validation.

A local test validates local connectivity and the extension flow. It does not
prove access from Render's IP address, third-party sign-in, actual delivery or
payment compatibility. Fixture tests are labelled separately from live read-only
searches. Inspect Render's per-store search error logs if its results differ.
