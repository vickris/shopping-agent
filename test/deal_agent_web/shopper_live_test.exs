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

    assert has_element?(
             view,
             "#chat-messages",
             "Hello shopper"
           )
  end

  test "clear list command clears the shopping list", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, "/")

    view
    |> form("#shopping-item-form",
      shopping_item: %{
        item_name: "Milk",
        quantity: "1",
        unit: "litre"
      }
    )
    |> render_submit()

    assert has_element?(
             view,
             "[id^='shopping-item-']",
             "Milk"
           )

    view
    |> form("#chat-form",
      chat: %{message: "clear list"}
    )
    |> render_submit()

    refute has_element?(
             view,
             "[id^='shopping-item-']",
             "Milk"
           )
  end
end
