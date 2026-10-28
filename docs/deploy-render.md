# Deploy the friends beta on Render

This deployment supports chat, supermarket searches, product selection and totals.
Checkout and manual store-window controls are disabled: a browser running on the
server cannot hand its cart to a friend's phone. Remote checkout needs a separate
implementation. The existing local development flow remains available.

## Create the deployment

1. Create an account at https://dashboard.render.com/register using GitHub.
2. Push the deployment commit to `vickris/shopping-agent` after authorizing the
   push. In Render choose **New → Blueprint** and connect that repository, granting
   access only to the repository needed. Select the branch containing `render.yaml`.
3. Review the resources before creating them. The Blueprint requests one paid
   `2c-4g` web service in Frankfurt and a free PostgreSQL database. Check Render's
   displayed current price; this is not a free web deployment. The free database
   expires after 30 days and must be upgraded to keep it beyond the beta.
4. Enter `OPENAI_API_KEY` directly in Render's secret environment field. Do not
   paste it into chat, source files or build arguments.
5. Create the Blueprint. The Docker build compiles the Phoenix release, installs
   the matching Firefox and Chromium binaries and checks that both launch as the
   unprivileged runtime user. The pre-deploy command runs database migrations.
6. When healthy, open the HTTPS service URL. Get the generated `BETA_PASSWORD`
   from the service environment settings and sign in with username `friends`.
   Share the URL and password privately with invited testers.

Render supplies the public hostname automatically. `/health` is public and checks
database connectivity; the shopping interface requires the beta password.

## Verify before inviting friends

If an initial attempt used Render's native **Elixir** runtime, create a new
**Docker** web service from this repository or use **New → Blueprint**. Do not
reuse the native service's build/start commands: the Dockerfile owns those steps
and installs the required browser engines and system libraries. The native
Elixir service can be removed once the Docker service has been verified.

- Confirm `/health` returns `{"status":"ok"}`.
- Open the homepage in a private browser session and verify the password prompt.
- Allow browser location access, then search for milk and select a product.
- Check results and totals from each available supermarket. A successful image
  build proves the browser engines launch, but store access from Render's network
  still needs this live check; retailer blocking can differ from a local machine.
- Try from a phone on a different network. Checkout should say it is unavailable.

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
browser state, but all invitees share the beta password and the model API budget.
Set an appropriate provider budget and rotate the beta password if needed.

Automatic deploys are off to avoid interrupting active shoppers on every push.
Use Render's manual deploy action for subsequent releases. Inspect application
logs for errors without sharing API keys, passwords or store session data.

The native production release, authentication gate and browser engines have been
tested locally. A Linux Docker build must still complete on Render: this workspace
does not have a Docker engine installed.

References: [Blueprint specification](https://render.com/docs/blueprint-spec),
[free database limits](https://render.com/docs/free),
[Playwright browser installation](https://playwright.dev/docs/browsers).
