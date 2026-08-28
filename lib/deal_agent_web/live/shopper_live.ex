defmodule DealAgentWeb.ShopperLive do
  use DealAgentWeb, :live_view

  alias DealAgent.Shopping.Item
  alias DealAgent.Shopping.ShoppingList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:shopping_list, ShoppingList.new())
     |> assign_form("")}
  end

  @impl true
  def handle_event(
        "add-item",
        %{
          "shopping_item" => %{
            "item_name" => name
          }
        },
        socket
      ) do
    case String.trim(name) do
      "" ->
        {:noreply, socket}

      name ->
        item = Item.new(name)

        shopping_list =
          ShoppingList.add_item(
            socket.assigns.shopping_list,
            item
          )

        {:noreply,
         socket
         |> assign(:shopping_list, shopping_list)
         |> assign_form("")}
    end
  end

  @impl true
  def handle_event(
        "update-item-name",
        %{"new_name" => new_name},
        socket
      ) do
    {:noreply, assign(socket, :item_name, new_name)}
  end

  @impl true
  def handle_event(
        "remove-item",
        %{"id" => item_id},
        socket
      ) do
    shopping_list =
      ShoppingList.remove_item(
        socket.assigns.shopping_list,
        item_id
      )

    {:noreply,
     assign(
       socket,
       :shopping_list,
       shopping_list
     )}
  end

  defp assign_form(socket, item_name) do
    assign(
      socket,
      :form,
      to_form(
        %{"item_name" => item_name},
        as: :shopping_item
      )
    )
  end
end
