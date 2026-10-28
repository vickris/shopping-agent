defmodule DealAgentWeb.Plugs.BetaAccess do
  @moduledoc "Optional shared-password gate for a small friends-only preview."
  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:deal_agent, :beta_auth) do
      nil -> conn
      credentials -> Plug.BasicAuth.basic_auth(conn, credentials)
    end
  end
end
