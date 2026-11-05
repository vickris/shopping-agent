defmodule DealAgentWeb.RemoteCheckoutTest do
  use DealAgentWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    keys = [:remote_checkout_enabled, :local_browser_enabled, :require_delivery_location]
    old = Map.new(keys, &{&1, Application.get_env(:deal_agent, &1)})
    Application.put_env(:deal_agent, :remote_checkout_enabled, true)
    Application.put_env(:deal_agent, :local_browser_enabled, false)
    Application.put_env(:deal_agent, :require_delivery_location, true)

    on_exit(fn ->
      for {key, value} <- old do
        if is_nil(value),
          do: Application.delete_env(:deal_agent, key),
          else: Application.put_env(:deal_agent, key, value)
      end
    end)

    :ok
  end

  test "hosted shoppers prepare the existing basket and control a private view", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")

    render_hook(view, "location-detected", %{
      "latitude" => -1.29,
      "longitude" => 36.82,
      "accuracy" => 100
    })

    wait_until(fn -> has_element?(view, "#carrefour-delivery", "Location confirmed") end)
    view |> form("#chat-form", chat: %{message: "2 litres of milk"}) |> render_submit()
    render_async(view, 1000)
    render_async(view, 1000)
    wait_until(fn -> has_element?(view, ".carrefour-product button") end)
    view |> element(".carrefour-product button") |> render_click()

    view
    |> element("button.shop-now[phx-value-store='carrefour']:not([disabled])")
    |> render_click()

    open = "button[phx-click='cart-window'][phx-value-store='carrefour'][phx-value-action='open']"
    wait_until(fn -> has_element?(view, open, "Continue to checkout") end)
    view |> element(open) |> render_click()
    assert has_element?(view, "#private-checkout", "Private Carrefour checkout")
    assert has_element?(view, "#private-checkout [phx-hook='RemoteCheckout']")
    assert has_element?(view, "#private-checkout input[type='password'][data-remote-input]")
    render_hook(view, "remote-control", %{"remote_input" => %{"type" => "frame"}})
    refute render(view) =~ "data:image"
    view |> element("button[phx-click='remote-close']") |> render_click()
    refute has_element?(view, "#private-checkout")
    view |> element(open) |> render_click()
    assert has_element?(view, "#private-checkout")
    view |> element("#private-checkout button[phx-value-action='close']") |> render_click()
    wait_until(fn -> not has_element?(view, "#private-checkout") end)
    assert has_element?(view, "#carrefour-cart-status", "closed")
  end

  defp wait_until(check, attempts \\ 150)
  defp wait_until(_, 0), do: flunk("remote checkout did not reach expected state")

  defp wait_until(check, attempts) do
    unless check.() do
      Process.sleep(10)
      wait_until(check, attempts - 1)
    end
  end
end
