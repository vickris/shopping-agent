# Keep builder and runner on Debian bookworm so the release's native libraries match.
FROM node:22-bookworm-slim AS node
FROM hexpm/elixir:1.18.4-erlang-27.3.4.16-debian-bookworm-20260824-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

WORKDIR /app
ENV MIX_ENV=prod ERL_FLAGS="+S 4:4"
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile
COPY assets/package.json assets/package-lock.json assets/
RUN npm ci --prefix assets --omit=dev
COPY priv/carrefour_browser/package.json priv/carrefour_browser/package-lock.json priv/carrefour_browser/
RUN npm ci --prefix priv/carrefour_browser --omit=dev
COPY priv priv
COPY assets assets
COPY lib lib
RUN mix assets.setup && mix assets.deploy && mix compile
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM node AS runner
WORKDIR /app
ENV NODE_ENV=production LANG=C.UTF-8 MIX_ENV=prod \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright PHX_SERVER=true PORT=4000 ERL_FLAGS="+S 2:2" \
    RELEASE_DISTRIBUTION=none
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libstdc++6 libncurses6 openssl tini \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder --chown=node:node /app/_build/prod/rel/deal_agent ./
# Install the exact browser versions required by the committed Playwright lockfile.
RUN node lib/deal_agent-*/priv/carrefour_browser/node_modules/playwright/cli.js \
    install --with-deps --no-shell chromium firefox \
    && rm -rf /var/lib/apt/lists/*
USER node
# Fail the image build if browser binaries, permissions or OS libraries are missing.
RUN node lib/deal_agent-*/priv/carrefour_browser/smoke.mjs
EXPOSE 4000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/bin/server"]
