defmodule DealAgentWeb.BrowserCheckoutTest do
  use DealAgentWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    keys = [:browser_checkout_enabled, :local_browser_enabled, :remote_checkout_enabled]
    old = Map.new(keys, &{&1, Application.get_env(:deal_agent, &1)})
    Application.put_env(:deal_agent, :browser_checkout_enabled, true)
    Application.put_env(:deal_agent, :local_browser_enabled, false)
    Application.put_env(:deal_agent, :remote_checkout_enabled, true)

    on_exit(fn ->
      for {key, value} <- old do
        if is_nil(value),
          do: Application.delete_env(:deal_agent, key),
          else: Application.put_env(:deal_agent, key, value)
      end
    end)

    :ok
  end

  test "browser checkout exports only the selected basket and does not prepare a server cart", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    view |> form("#chat-form", chat: %{message: "2 litres of milk"}) |> render_submit()
    render_async(view, 1000)
    render_async(view, 1000)
    view |> element("button[phx-value-product-id='milk-1']") |> render_click()
    assert has_element?(view, "#carrefour-browser-checkout a[download]")

    view
    |> element("button.shop-now[phx-value-store='carrefour']", "Checkout in my browser")
    |> render_click()

    assert_push_event(view, "browser-basket", %{
      plan: %{version: 1, store: "carrefour", products: [%{id: "milk-1", packs: 2}]}
    })

    refute has_element?(view, "#carrefour-cart-status")
    refute has_element?(view, "#private-checkout")
  end
end
