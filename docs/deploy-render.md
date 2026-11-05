# Deploy the friends beta on Render

This deployment supports chat, supermarket searches, product selection, totals,
and private remote checkout for the stores with cart adapters (Carrefour,
Quickmart and Naivas). Foodplus checkout remains unsupported by its adapter.
Shoppers control the existing store browser inside the app, rather than receiving
an empty cart in a separate browser. The local desktop flow remains available.

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

Keep `LOCAL_BROWSER_ENABLED=false` on Render to disable desktop windows. Set
`REMOTE_CHECKOUT_ENABLED=true` to enable private in-app checkout. Both settings
are in the Blueprint; update the environment manually for an existing deployment.
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
- Try from a phone on a different network. Select a product, choose Shop now,
  wait for the verified cart, then choose Continue to checkout. Verify the store,
  branch, quantities and final total in the private view before payment. Do not
  place a real order just to test deployment.

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

## Private remote checkout

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
