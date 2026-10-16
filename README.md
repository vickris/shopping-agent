# DealAgent

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix

## Agent run logging

BeamAgent 0.3.x supplies the structured telemetry-to-Logger bridge. It is enabled
in `config/config.exs` with `config :beam_agent, :structured_logging, true`.
Restart `mix phx.server` after upgrading so BeamAgent attaches its supervised
logging handler.

Console logs are JSON lines in development and production. Run lifecycle records
include `beam_agent_event` (`beam_agent.run.start`, `beam_agent.run.stop`, or
`beam_agent.run.exception`) and an opaque `run_key` for correlation. Terminal
records include outcome, execution/verification status, iteration/tool-call
counts and error classification where available. Durations retain the package's
native `duration` and add `duration_ms`; timestamps are UTC. Verification,
compression and guardrail records currently do not carry a run key.

The formatter retains only an explicit operational metadata allowlist, including
Phoenix `request_id`. BeamAgent's bridge excludes prompts, shopping requests,
tool arguments/results, model responses and raw exception details. Ordinary app
messages remain ordinary app messages, encoded as JSON; this is not a general
redactor for arbitrary text logged elsewhere.

BeamAgent emits these events at info level. Tests keep the application's warning
threshold, while logging tests explicitly capture info events. To inspect agent
records from a saved console log, filter for a non-null `beam_agent_event` and
then group lifecycle events by `run_key`.

See the installed package's `deps/beam_agent/README.md` and
`deps/beam_agent/docs/structured-logging.md`. PostgreSQL trace history, the local
BeamAgent dashboard, token usage and cost reporting are separate opt-in features;
this logging setup does not enable them.
