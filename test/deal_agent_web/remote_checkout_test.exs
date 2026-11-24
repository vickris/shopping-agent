defmodule DealAgentWeb.RemoteCheckoutTest do
  use DealAgentWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defmodule OldPriceClient do
    def search(query) do
      {:ok, products} = DealAgent.Supermarkets.Naivas.MockClient.search(query)
      {:ok, Enum.map(products, &Map.update!(&1, :price, fn price -> Decimal.add(price, 1) end))}
    end
  end

  setup do
    keys = [
      :remote_checkout_enabled,
      :local_browser_enabled,
      :require_delivery_location,
      :browser_checkout_enabled,
      :local_helper_enabled,
      :naivas_search_options
    ]

    old = Map.new(keys, &{&1, Application.get_env(:deal_agent, &1)})
    Application.put_env(:deal_agent, :remote_checkout_enabled, true)
    Application.put_env(:deal_agent, :local_helper_enabled, true)
    Application.put_env(:deal_agent, :browser_checkout_enabled, true)
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
    refute has_element?(view, "#carrefour-browser-checkout")

    render_hook(view, "location-detected", %{
      "latitude" => -1.29,
      "longitude" => 36.82,
      "accuracy" => 100
    })

    wait_until(fn -> has_element?(view, "#carrefour-delivery", "Location confirmed") end)

    view
    |> element("#carrefour-delivery button[phx-value-action='open']")
    |> render_click()

    assert has_element?(view, "#private-checkout", "Confirm saved delivery address")
    render_hook(view, "remote-control", %{"remote_input" => %{"type" => "frame"}})
    view |> element("button[phx-click='remote-close']") |> render_click()
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
    assert has_element?(view, "#private-checkout", "Checkout at Carrefour")
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

  test "Naivas address can be saved in app without geolocation or a separate browser window", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#naivas-address-setup button", "Set Naivas delivery address")
    view |> element("#naivas-address-setup button") |> render_click()
    wait_until(fn -> has_element?(view, "#private-checkout", "Naivas delivery address") end)
    refute has_element?(view, "#private-checkout", "Private Naivas checkout")
    view |> element("#private-checkout button[phx-value-action='confirm']") |> render_click()
    wait_until(fn -> has_element?(view, "#naivas-delivery", "Location confirmed") end)
    refute has_element?(view, "#private-checkout")
  end

  test "selecting Naivas items then saving the address retains unchanged choices and prepares the same session",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    view |> form("#chat-form", chat: %{message: "2 litres of milk"}) |> render_submit()
    render_async(view, 1000)

    view
    |> element(".naivas-product button[phx-value-product-id='naivas-milk']")
    |> render_click()

    assert has_element?(view, ".naivas-selection", "4 packs")
    view |> element("button.shop-now[phx-value-store='naivas']") |> render_click()
    wait_until(fn -> has_element?(view, "#private-checkout", "Naivas delivery address") end)
    view |> element("#private-checkout button[phx-value-action='confirm']") |> render_click()
    wait_until(fn -> has_element?(view, "#naivas-delivery", "Location confirmed") end)
    render_async(view, 1000)
    assert has_element?(view, ".naivas-selection", "4 packs")
    view |> element("button.shop-now[phx-value-store='naivas']") |> render_click()
    open = "button[phx-click='cart-window'][phx-value-store='naivas'][phx-value-action='open']"
    wait_until(fn -> has_element?(view, open, "Continue to checkout") end)
    view |> element(open) |> render_click()
    assert has_element?(view, "#private-checkout", "Checkout at Naivas")
    refute has_element?(view, "a[href$='shopping-agent-local-helper.zip']")
    refute has_element?(view, "a[href$='shopping-agent-extension.zip']")
  end

  test "Naivas requires a new selection when the saved address changes the compared price", %{
    conn: conn
  } do
    Application.put_env(:deal_agent, :naivas_search_options, client: OldPriceClient)
    {:ok, view, _} = live(conn, "/")
    view |> form("#chat-form", chat: %{message: "2 litres of milk"}) |> render_submit()
    render_async(view, 1000)

    view
    |> element(".naivas-product button[phx-value-product-id='naivas-milk']")
    |> render_click()

    view |> element("button.shop-now[phx-value-store='naivas']") |> render_click()
    wait_until(fn -> has_element?(view, "#private-checkout", "Naivas delivery address") end)
    view |> element("#private-checkout button[phx-value-action='confirm']") |> render_click()
    wait_until(fn -> has_element?(view, "#naivas-delivery", "Location confirmed") end)
    render_async(view, 1000)
    refute has_element?(view, ".naivas-selection")
    assert has_element?(view, "#flash-info", "changed or unavailable items")
    refute has_element?(view, "#naivas-cart-status")
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
