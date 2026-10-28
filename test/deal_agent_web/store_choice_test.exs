defmodule DealAgentWeb.StoreChoiceTest do
  use DealAgentWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  for {store, mock} <- [
        carrefour: DealAgent.Supermarkets.Carrefour.MockClient,
        quickmart: DealAgent.Supermarkets.Quickmart.MockClient,
        naivas: DealAgent.Supermarkets.Naivas.MockClient,
        foodplus: DealAgent.Supermarkets.Foodplus.MockClient
      ] do
    defmodule Module.concat(__MODULE__, store) do
      @store store
      @mock mock
      def search(query) do
        send(Process.whereis(DealAgent.StoreChoiceOwner), {:store_search, @store, query})
        @mock.search(query)
      end
    end
  end

  setup do
    Process.register(self(), DealAgent.StoreChoiceOwner)

    for store <- ~w(carrefour quickmart naivas foodplus)a do
      key = String.to_existing_atom("#{store}_search_options")
      old = Application.get_env(:deal_agent, key)
      Application.put_env(:deal_agent, key, client: Module.concat(__MODULE__, store))
      on_exit(fn -> Application.put_env(:deal_agent, key, old) end)
    end

    :ok
  end

  defp chat(view, message) do
    view |> form("#chat-form", chat: %{message: message}) |> render_submit()
    render_async(view, 2000)
    render_async(view, 2000)
  end

  test "prose searches only the requested stores without adding UI panels", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    chat(view, "I want to shop for milk and ice and water. Compare Naivas and Carrefour.")

    for store <- [:naivas, :carrefour],
        query <- ~w(milk ice water),
        do: assert_receive({:store_search, ^store, ^query})

    refute_receive {:store_search, _, _}
    assert has_element?(view, ".store-heading.store-naivas")
    assert has_element?(view, ".store-heading.store-carrefour")
    refute has_element?(view, ".store-heading.store-quickmart")
    refute has_element?(view, ".store-heading.store-foodplus")
    refute has_element?(view, "#comparison-scope")
    refute has_element?(view, "#available-supermarkets")

    assert length(
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("#supermarket-results tbody > tr")
           ) == 3

    view |> element("[phx-value-product-id='milk-1']") |> render_click()
    assert has_element?(view, ".carrefour-selection", "Selected for milk")
    assert has_element?(view, "#carrefour-total", "KES 189.00")
  end

  test "follow-up store changes reuse the existing list and persist for later items", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    chat(view, "I want to shop for milk and ice and water. Compare Naivas and Carrefour.")

    for store <- [:naivas, :carrefour],
        query <- ~w(milk ice water),
        do: assert_receive({:store_search, ^store, ^query})

    chat(view, "Compare Quickmart")
    for query <- ~w(milk ice water), do: assert_receive({:store_search, :quickmart, ^query})
    refute_receive {:store_search, _, _}
    refute has_element?(view, ".store-heading.store-naivas")
    assert has_element?(view, ".store-heading.store-quickmart")
    chat(view, "Add ice")
    assert_receive {:store_search, :quickmart, "ice"}
    refute_receive {:store_search, _, _}
    chat(view, "Compare all supermarkets")

    for store <- [:carrefour, :quickmart, :naivas, :foodplus] do
      assert has_element?(view, ".store-heading.store-#{store}")
      assert_receive {:store_search, ^store, "milk"}
    end
  end

  test "supported stores are explained in chat and unsupported stores cause no searches", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    chat(view, "Which supermarkets are available?")

    assert has_element?(
             view,
             "#chat-messages",
             "You can compare Carrefour, Quickmart, Naivas, Foodplus"
           )

    refute_receive {:store_search, _, _}
    chat(view, "Milk from Tesco")
    assert has_element?(view, "#chat-messages", "Please choose from these supermarkets")
    refute has_element?(view, "#supermarket-results")
    refute_receive {:store_search, _, _}
  end

  test "store changes cannot hide an active cart", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    chat(view, "Add milk")

    for store <- [:carrefour, :quickmart, :naivas, :foodplus],
        do: assert_receive({:store_search, ^store, "milk"})

    view |> element("[phx-value-product-id='milk-1']") |> render_click()
    view |> element("button[phx-click='shop-now'][phx-value-store='carrefour']") |> render_click()
    chat(view, "Compare Quickmart")
    assert has_element?(view, "#chat-messages", "Close the active cart")
    assert has_element?(view, ".store-heading.store-carrefour")
    refute_receive {:store_search, _, _}
  end
end
