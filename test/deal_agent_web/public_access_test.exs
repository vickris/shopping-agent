defmodule DealAgentWeb.PublicAccessTest do
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

  test "homepage is public even with legacy beta credentials configured", %{conn: conn} do
    Application.put_env(:deal_agent, :beta_auth,
      username: "friends",
      password: "fixture-password"
    )

    response = get(conn, "/")
    assert response.status == 200
    assert response.resp_body =~ "Shopping assistant"
    assert get_resp_header(response, "www-authenticate") == []
    assert json_response(get(conn, "/health"), 200) == %{"status" => "ok"}
  end

  test "homepage is public without credentials", %{conn: conn} do
    Application.delete_env(:deal_agent, :beta_auth)
    assert get(conn, "/").status == 200
  end
end
