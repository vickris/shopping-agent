defmodule DealAgent.Repo do
  use Ecto.Repo,
    otp_app: :deal_agent,
    adapter: Ecto.Adapters.Postgres
end
