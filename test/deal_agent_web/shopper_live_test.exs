defmodule DealAgentWeb.ShopperLiveTest do
  use DealAgentWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "adds a chat message", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, "/")

    view
    |> form("#chat-form",
      chat: %{
        message: "Hello shopper"
      }
    )
    |> render_submit()

    refute has_element?(view, "#shopping-item-form")

    assert has_element?(
             view,
             "#chat-messages",
             "Hello shopper"
           )
  end

  test "clear list command clears the shopping list", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, "/")

    view |> form("#chat-form", chat: %{message: "1 litre of milk"}) |> render_submit()
    render_async(view, 1000)

    assert has_element?(
             view,
             "[id^='shopping-item-']",
             "milk"
           )

    view
    |> form("#chat-form",
      chat: %{message: "clear list"}
    )
    |> render_submit()

    refute has_element?(
             view,
             "[id^='shopping-item-']",
             "milk"
           )
  end

  test "adds an item through chat asynchronously", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, "/")

    html =
      view
      |> form("#chat-form",
        chat: %{
          message: "Add two litres of milk"
        }
      )
      |> render_submit()

    assert html =~ "agent-thinking"

    render_async(view, 1000)

    assert has_element?(
             view,
             "[id^='shopping-item-']",
             "milk"
           )

    refute has_element?(
             view,
             "#agent-thinking"
           )
  end

  test "bare quantity request flows from chat to the Carrefour column", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> form("#chat-form", chat: %{message: "2 litres of milk"}) |> render_submit()
    render_async(view, 1000)
    render_async(view, 1000)

    assert has_element?(view, "#supermarket-results th", "Carrefour")
    assert has_element?(view, "#supermarket-results", "Requested: 2 L")
    assert has_element?(view, ".carrefour-product", "Brookside Whole Milk 1L")
    assert has_element?(view, ".carrefour-product", "KES 189.00")
    assert has_element?(view, ".carrefour-product", "500 ml")
    refute has_element?(view, ".carrefour-loading")
    refute has_element?(view, ".carrefour-error")
  end

  test "no returned products and failed searches have distinct states", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    add_item(view, "bread")
    render_async(view, 1000)
    assert has_element?(view, ".carrefour-empty", "No products returned")

    add_item(view, "unreadable")
    render_async(view, 1000)
    assert has_element?(view, ".carrefour-error", "did not return a readable search page")
    assert has_element?(view, ".carrefour-empty", "No products returned")
  end

  test "removing an item while search runs ignores its late result", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    add_item(view, "slow milk")
    assert has_element?(view, ".carrefour-loading")
    view |> element("[phx-click='remove-item']") |> render_click()
    render_async(view, 1000)
    refute has_element?(view, "#supermarket-results")
  end

  test "clear list removes the results and ignores unfinished searches", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    add_item(view, "slow milk")
    view |> form("#chat-form", chat: %{message: "clear list"}) |> render_submit()
    render_async(view, 1000)
    refute has_element?(view, "#supermarket-results")
  end

  test "a search can be retried", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    add_item(view, "milk")
    render_async(view, 1000)
    view |> element("[phx-click='retry-search'][phx-value-store='carrefour']") |> render_click()
    render_async(view, 1000)
    assert has_element?(view, ".carrefour-product", "KES 189.00")
  end

  test "selects, replaces, edits and clears a product with deterministic totals", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    add_item(view, "milk")
    render_async(view, 1000)
    assert has_element?(view, "#carrefour-total", "Incomplete")

    view
    |> element("[phx-click='select-product'][phx-value-product-id='milk-500']")
    |> render_click()

    assert has_element?(view, ".carrefour-selection", "4 packs · Row cost: KES 396.00")
    assert has_element?(view, "[phx-value-product-id='milk-500'][aria-pressed='true']")
    assert has_element?(view, "#carrefour-total", "KES 396.00")
    refute has_element?(view, "#carrefour-total", "Incomplete")

    view
    |> element("[phx-click='select-product'][phx-value-product-id='milk-1']")
    |> render_click()

    assert has_element?(view, ".carrefour-selection", "2 packs · Row cost: KES 378.00")
    view |> form(".carrefour-selection form", %{packs: "3"}) |> render_submit()
    assert has_element?(view, "#carrefour-total", "KES 567.00")
    view |> form(".carrefour-selection form", %{packs: "0"}) |> render_submit()
    assert has_element?(view, "#carrefour-total", "KES 567.00")
    view |> element("[phx-click='clear-selection']") |> render_click()
    refute has_element?(view, ".carrefour-selection")
    assert has_element?(view, "#carrefour-total", "Incomplete")
  end

  test "refresh invalidates selected prices and forged product IDs are ignored", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    add_item(view, "milk")
    render_async(view, 1000)
    render_click(view, "select-product", %{"item-id" => "missing", "product-id" => "milk-1"})
    refute has_element?(view, ".carrefour-selection")

    view
    |> element("[phx-click='select-product'][phx-value-product-id='milk-1']")
    |> render_click()

    view |> element("[phx-click='retry-search'][phx-value-store='carrefour']") |> render_click()
    render_async(view, 1000)
    refute has_element?(view, ".carrefour-selection")
    assert has_element?(view, "#carrefour-total", "Incomplete")
  end

  test "three stores search through chat and selections and refreshes remain independent", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    view |> form("#chat-form", chat: %{message: "2 litres of milk"}) |> render_submit()
    render_async(view, 1000)
    render_async(view, 1000)
    assert has_element?(view, ".carrefour-product")
    assert has_element?(view, ".quickmart-product", "Quickmart Milk 500Ml")
    assert has_element?(view, ".naivas-product", "Naivas Milk 500Ml")
    view |> element("[phx-value-product-id='naivas-milk']") |> render_click()
    assert has_element?(view, "#naivas-total", "KES 280.00")
    view |> element("[phx-value-product-id='milk-1']") |> render_click()
    view |> element("[phx-value-product-id='quick-milk']") |> render_click()
    assert has_element?(view, "#carrefour-total", "KES 378.00")
    assert has_element?(view, "#quickmart-total", "KES 260.00")
    view |> form(".quickmart-selection form", %{packs: "5"}) |> render_submit()
    assert has_element?(view, "#quickmart-total", "KES 325.00")
    assert has_element?(view, "#carrefour-total", "KES 378.00")
    view |> element("[phx-click='retry-search'][phx-value-store='quickmart']") |> render_click()
    render_async(view, 1000)
    refute has_element?(view, ".quickmart-selection")
    assert has_element?(view, ".carrefour-selection")
    assert has_element?(view, ".naivas-selection")
    assert has_element?(view, "#naivas-total", "KES 280.00")
    view |> form(".naivas-selection form", %{packs: "5"}) |> render_submit()
    assert has_element?(view, "#naivas-total", "KES 350.00")
    assert has_element?(view, "#carrefour-total", "KES 378.00")
    assert has_element?(view, "#quickmart-total", "Incomplete")
    view |> element("[phx-click='remove-item']") |> render_click()
    refute has_element?(view, "#supermarket-results")
  end

  test "provider failures show actionable errors instead of asking users to rephrase", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, messages: [], agent_status: :thinking}
    }

    {:noreply, result} =
      DealAgentWeb.ShopperLive.handle_async(
        {:interpret_message, "test"},
        {:ok, {:error, {:openai_request_failed, %Req.TransportError{reason: :closed}}}},
        socket
      )

    assert List.last(result.assigns.messages).content =~ "OpenAI connection failed (closed)"
    assert result.assigns.agent_status == :idle

    {:noreply, result} =
      DealAgentWeb.ShopperLive.handle_async(
        {:interpret_message, "test"},
        {:ok,
         {:error, {:openai_http_error, 429, %{"error" => %{"code" => "insufficient_quota"}}}}},
        socket
      )

    assert List.last(result.assigns.messages).content =~ "credits"
    refute has_element?(view, ".carrefour-product")
  end

  test "missing quantities are labelled and selected as an adjustable single pack", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    view |> form("#chat-form", chat: %{message: "add milk"}) |> render_submit()
    render_async(view, 1000)
    render_async(view, 1000)
    assert has_element?(view, "#supermarket-results", "Quantity unspecified")
    view |> element("[phx-value-product-id='milk-500']") |> render_click()
    assert has_element?(view, ".carrefour-selection", "1 packs · Row cost: KES 99.00")
    assert has_element?(view, ".carrefour-selection", "Quantity unspecified · starts at 1 pack")
    view |> form(".carrefour-selection form", %{packs: "2"}) |> render_submit()
    assert has_element?(view, "#carrefour-total", "KES 198.00")
  end

  test "multi-item prose adds separate comparison rows in one interpretation", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")

    view
    |> form("#chat-form",
      chat: %{message: "I want 2 litres of milk, eggs, baking soda kiwi and mangoes"}
    )
    |> render_submit()

    render_async(view, 1000)
    render_async(view, 1000)

    assert length(
             view
             |> element("#supermarket-results tbody")
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.find("tr")
           ) == 5

    assert has_element?(view, "#supermarket-results", "baking soda")
    assert has_element?(view, "#supermarket-results", "Requested: 2 L")
    assert has_element?(view, "#supermarket-results", "Quantity unspecified")
    assert has_element?(view, ".carrefour-product")
    assert has_element?(view, ".quickmart-product")
    assert has_element?(view, ".naivas-product")
    assert has_element?(view, "#chat-messages", "Added 5 items")
  end

  test "cell filters are independent and do not change selections or totals", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    add_item(view, "milk")
    render_async(view, 1000)
    view |> element("[phx-value-product-id='milk-1']") |> render_click()

    view
    |> form(".candidate-filter[phx-change='filter-products'][id^='carrefour-filter-']", %{
      query: "500ML"
    })
    |> render_change()

    assert has_element?(view, ".carrefour-product", "500ml")
    refute has_element?(view, ".carrefour-product", "Brookside Whole Milk 1L")
    assert has_element?(view, ".carrefour-selection", "Brookside Whole Milk 1L")
    assert has_element?(view, "#carrefour-total", "KES 378.00")
    assert has_element?(view, ".quickmart-product")
    view |> form("form[id^='carrefour-filter-']", %{query: "no match"}) |> render_change()
    assert has_element?(view, ".candidate-filter-empty", "No matching products")
    view |> form("form[id^='carrefour-filter-']", %{query: ""}) |> render_change()
    assert has_element?(view, ".carrefour-product", "Brookside Whole Milk 1L")
  end

  test "shop now needs complete selections and alerts only after cart verification", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    add_item(view, "milk")
    render_async(view, 1000)
    assert has_element?(view, "button[phx-click='shop-now'][disabled]")
    view |> element("[phx-value-product-id='milk-1']") |> render_click()
    refute has_element?(view, "button[phx-click='shop-now'][disabled]")
    view |> element("button[phx-click='shop-now']") |> render_click()

    assert_push_event(
      view,
      "cart-notification",
      %{
        type: "success",
        message:
          "Your Carrefour cart is filled and verified. Review it and pay in the Carrefour browser window."
      },
      3000
    )

    assert has_element?(view, "#carrefour-cart-status", "Cart ready")
    view |> element("button[phx-value-action='close']") |> render_click()
  end

  defp add_item(view, name) do
    render_submit(view, "add-item", %{
      "shopping_item" => %{"item_name" => name, "quantity" => "2", "unit" => "litre"}
    })
  end
end
