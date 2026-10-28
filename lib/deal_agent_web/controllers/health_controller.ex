defmodule DealAgentWeb.HealthController do
  use DealAgentWeb, :controller

  def show(conn, _) do
    case Ecto.Adapters.SQL.query(DealAgent.Repo, "SELECT 1", [],
           timeout: 2_000,
           pool_timeout: 2_000
         ) do
      {:ok, _} -> json(conn, %{status: "ok"})
      _ -> conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    end
  rescue
    _ -> conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
  end
end
