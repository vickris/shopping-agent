defmodule DealAgentWeb.OnlinePreviewTest do
  use DealAgentWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    old = Application.get_env(:deal_agent, :local_browser_enabled)
    Application.put_env(:deal_agent, :local_browser_enabled, false)

    on_exit(fn ->
      if is_nil(old),
        do: Application.delete_env(:deal_agent, :local_browser_enabled),
        else: Application.put_env(:deal_agent, :local_browser_enabled, old)
    end)

    :ok
  end

  test "online preview retains comparison and selection but cannot launch local windows or carts",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    view |> form("#chat-form", chat: %{message: "2 litres of milk"}) |> render_submit()
    render_async(view, 2000)
    render_async(view, 2000)
    assert has_element?(view, ".carrefour-product")
    view |> element("[phx-value-product-id='milk-1']") |> render_click()
    assert has_element?(view, ".carrefour-selection")
    assert has_element?(view, "#carrefour-total button[disabled]", "Checkout unavailable")
    refute has_element?(view, "#carrefour-delivery-form")

    for {event, params} <- [
          {"shop-now", %{"store" => "carrefour"}},
          {"shop-now", %{"store" => "foodplus"}},
          {"setup-delivery", %{"store" => "carrefour", "area" => "Syokimau"}},
          {"delivery-window", %{"store" => "carrefour", "action" => "open"}},
          {"cart-window", %{"store" => "carrefour", "action" => "open"}}
        ] do
      assert render_click(view, event, params) =~ "checkout are not enabled yet"
    end

    refute has_element?(view, "#carrefour-cart-status")
  end
end
