defmodule DealAgentWeb.BetaAccessTest do
  use DealAgentWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:deal_agent, :beta_auth)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:deal_agent, :beta_auth, previous),
        else: Application.delete_env(:deal_agent, :beta_auth)
    end)

    :ok
  end

  test "beta gate protects the page but leaves the health check available", %{conn: conn} do
    Application.put_env(:deal_agent, :beta_auth,
      username: "friends",
      password: "fixture-password"
    )

    assert get(conn, "/").status == 401
    assert get(conn, "/health").status == 200

    authenticated =
      conn
      |> put_req_header(
        "authorization",
        Plug.BasicAuth.encode_basic_auth("friends", "fixture-password")
      )
      |> get("/")

    assert authenticated.status == 200
    assert authenticated.resp_body =~ "Shopping assistant"

    assert conn
           |> put_req_header(
             "authorization",
             Plug.BasicAuth.encode_basic_auth("friends", "wrong")
           )
           |> get("/")
           |> Map.fetch!(:status) == 401
  end

  test "development remains accessible when no beta gate is configured", %{conn: conn} do
    Application.delete_env(:deal_agent, :beta_auth)
    assert get(conn, "/").status == 200
    assert json_response(get(conn, "/health"), 200) == %{"status" => "ok"}
  end
end
