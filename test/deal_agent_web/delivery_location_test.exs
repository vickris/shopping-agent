defmodule DealAgentWeb.DeliveryLocationTest do
  use DealAgentWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    old = Application.get_env(:deal_agent, :require_delivery_location)
    Application.put_env(:deal_agent, :require_delivery_location, true)
    on_exit(fn -> Application.put_env(:deal_agent, :require_delivery_location, old) end)
    :ok
  end

  test "confirmed location drives in-cell searches and the same cart session", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    view |> form("#chat-form", chat: %{message: "2 litres of milk"}) |> render_submit()
    render_async(view, 1000)
    assert has_element?(view, ".carrefour-error", "automatic location setup")
    refute has_element?(view, ".carrefour-product")
    view |> form("#carrefour-delivery-form", %{area: "Syokimau"}) |> render_submit()

    wait_until(fn ->
      has_element?(view, "#carrefour-delivery button[phx-value-action='confirm']")
    end)

    view |> element("#carrefour-delivery button[phx-value-action='confirm']") |> render_click()
    wait_until(fn -> has_element?(view, "#carrefour-delivery", "Location confirmed") end)
    render_async(view, 1000)
    assert has_element?(view, ".carrefour-product", "Milk 500ml")
    assert has_element?(view, "#carrefour-delivery", "Syokimau")
    refute has_element?(view, ".quickmart-product")
    view |> form("form[id^='carrefour-filter-']", %{query: "milk"}) |> render_submit()
    render_async(view, 1000)
    view |> element("[phx-value-product-id='247170']") |> render_click()
    assert has_element?(view, "#carrefour-total", "KES 260.00")
    view |> element("button[phx-click='shop-now'][phx-value-store='carrefour']") |> render_click()

    assert_push_event(
      view,
      "cart-notification",
      %{type: "success", message: "Cart filled at the confirmed delivery location."},
      3000
    )

    open = "button[phx-click='cart-window'][phx-value-action='open'][phx-value-store='carrefour']"
    assert has_element?(view, open, "Continue to checkout")
    view |> element(open) |> render_click()
    wait_until(fn -> has_element?(view, open <> "[disabled]", "Opening cart") end)
    wait_until(fn -> has_element?(view, open <> ":not([disabled])", "Continue to checkout") end)
    assert has_element?(view, "#carrefour-delivery", "Location confirmed")
    assert has_element?(view, "#carrefour-cart-status", "Cart filled")

    render_hook(view, "location-detected", %{
      "latitude" => -1.367,
      "longitude" => 36.936,
      "accuracy" => 100
    })

    assert has_element?(view, "#location-message", "Close your active cart windows")
    assert has_element?(view, "#carrefour-delivery", "Syokimau")

    view
    |> element(
      "button[phx-click='cart-window'][phx-value-action='close'][phx-value-store='carrefour']"
    )
    |> render_click()

    wait_until(fn -> has_element?(view, "#carrefour-delivery-form") end)
    refute has_element?(view, ".carrefour-selection")
    refute has_element?(view, ".carrefour-product")
    assert has_element?(view, "#carrefour-total", "KES 0.00")
  end

  test "changing the location discards previous prices and requires confirmation again", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    view |> form("#carrefour-delivery-form", %{area: "Syokimau"}) |> render_submit()

    wait_until(fn ->
      has_element?(view, "#carrefour-delivery button[phx-value-action='confirm']")
    end)

    view |> element("#carrefour-delivery button[phx-value-action='confirm']") |> render_click()
    wait_until(fn -> has_element?(view, "#carrefour-delivery", "Location confirmed") end)
    view |> form("#chat-form", chat: %{message: "2 litres of milk"}) |> render_submit()
    render_async(view, 1000)
    render_async(view, 1000)
    assert has_element?(view, ".carrefour-product")
    view |> form("form[id^='carrefour-filter-']", %{query: "changed"}) |> render_submit()
    wait_until(fn -> has_element?(view, "#carrefour-delivery-form") end)
    refute has_element?(view, ".carrefour-product")
    view |> element("[phx-click='retry-search'][phx-value-store='carrefour']") |> render_click()
    assert has_element?(view, ".carrefour-error", "automatic location setup")
  end

  for store <- ~w(quickmart naivas) do
    test "#{store} confirmation shows progress, reports failure, and allows retry", %{conn: conn} do
      store = unquote(store)
      {:ok, view, _} = live(conn, "/")
      view |> form("##{store}-delivery-form", %{area: "Retry"}) |> render_submit()
      selector = "##{store}-delivery button[phx-value-action='confirm']"
      wait_until(fn -> has_element?(view, selector) end)
      view |> element(selector) |> render_click()
      assert has_element?(view, selector <> "[disabled]", "Checking location")

      wait_until(fn ->
        has_element?(view, "##{store}-delivery", "Save the store delivery address")
      end)

      refute has_element?(view, selector <> "[disabled]")
      refute has_element?(view, "##{store}-delivery", "Location confirmed")
      view |> element(selector) |> render_click()

      expected =
        if store == "naivas",
          do: "Area supplied · delivery unverified",
          else: "Location confirmed"

      wait_until(fn -> has_element?(view, "##{store}-delivery", expected) end)
    end
  end

  test "browser location selects all store sessions automatically and can replace a manual session",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    view |> form("#carrefour-delivery-form", %{area: "Syokimau"}) |> render_submit()

    wait_until(fn ->
      has_element?(view, "#carrefour-delivery button[phx-value-action='confirm']")
    end)

    render_hook(view, "location-detected", %{
      "latitude" => -1.367,
      "longitude" => 36.936,
      "accuracy" => 100
    })

    for store <- ~w(carrefour quickmart naivas) do
      wait_until(fn -> has_element?(view, "##{store}-delivery", "Location confirmed") end)
    end

    for store <- ~w(carrefour quickmart naivas) do
      refute has_element?(view, "##{store}-delivery button[phx-value-action='confirm']")
    end

    assert has_element?(view, "#location-message", "Select your products, then Shop now")
    assert has_element?(view, "#quickmart-delivery", "Nearby Quickmart")
    refute render(view) =~ "36.936"
    refute render(view) =~ "-1.367"
  end

  test "an automatic store failure can retry without asking for store confirmation", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")

    render_hook(view, "location-detected", %{
      "latitude" => -1.367,
      "longitude" => 36.936,
      "accuracy" => 100
    })

    wait_until(fn -> has_element?(view, "#naivas-delivery", "Location confirmed") end)

    {id, session} =
      Enum.find(:sys.get_state(DealAgent.Delivery.Sessions), fn {_, s} ->
        s.owner == view.pid and s.store == "naivas"
      end)

    event = %{
      "type" => "setup",
      "status" => "unavailable",
      "message" => "The store could not confirm automatically."
    }

    send(DealAgent.Delivery.Sessions, {session.port, {:data, {:eol, Jason.encode!(event)}}})
    retry = "#naivas-delivery button[phx-value-action='locate']"
    wait_until(fn -> has_element?(view, retry, "Retry automatically") end)
    refute has_element?(view, "#naivas-delivery button[phx-value-action='confirm']")
    assert :sys.get_state(DealAgent.Delivery.Sessions)[id].confirmed == false
    view |> element(retry) |> render_click()
    wait_until(fn -> has_element?(view, "#naivas-delivery", "Location confirmed") end)
    assert :sys.get_state(DealAgent.Delivery.Sessions)[id].confirmed
    refute has_element?(view, retry)
    assert has_element?(view, "#carrefour-delivery", "Location confirmed")
  end

  test "denied or invalid geolocation leaves manual area entry available", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    render_hook(view, "location-error", %{"reason" => "denied"})
    assert has_element?(view, "#location-message", "permission was denied")
    render_hook(view, "location-detected", %{"latitude" => 1000, "longitude" => 36})
    assert has_element?(view, "#location-message", "invalid location")
    assert has_element?(view, "#carrefour-delivery-form")
    assert has_element?(view, "#quickmart-delivery-form")
    assert has_element?(view, "#naivas-delivery-form")
  end

  defp wait_until(check, attempts \\ 150)
  defp wait_until(_, 0), do: flunk("location UI did not reach expected state")

  defp wait_until(check, attempts) do
    unless check.() do
      Process.sleep(10)
      wait_until(check, attempts - 1)
    end
  end
end
