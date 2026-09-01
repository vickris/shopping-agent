defmodule DealAgentWeb.ShopperLive do
  use DealAgentWeb, :live_view

  alias DealAgent.Chat.Message
  alias DealAgent.Shopping.Item
  alias DealAgent.Shopping.ShoppingList
  alias DealAgent.Shopping.IntentHandler
  alias DealAgent.Shopping.IntentParser

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:shopping_list, ShoppingList.new())
     |> assign(:units, Item.units())
     |> assign(:messages, [])
     |> assign_item_form()
     |> assign_chat_form()}
  end

  @impl true
  def handle_event(
        "add-item",
        %{
          "shopping_item" => %{
            "item_name" => name,
            "quantity" => quantity,
            "unit" => unit
          }
        },
        socket
      ) do
    with name when name != "" <- String.trim(name),
         {:ok, quantity} <- parse_quantity(quantity),
         {:ok, unit} <- parse_unit(unit) do
      item =
        Item.new(name,
          quantity: quantity,
          unit: unit
        )

      shopping_list =
        ShoppingList.add_item(
          socket.assigns.shopping_list,
          item
        )

      {:noreply,
       socket
       |> assign(:shopping_list, shopping_list)
       |> assign_item_form(%{
         "item_name" => "",
         "quantity" => "1",
         "unit" => "each"
       })}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid shopping item")}
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

  @impl true
  def handle_event(
        "send-message",
        %{"chat" => %{"message" => content}},
        socket
      ) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      intent =
        IntentParser.parse(content)

      {
        shopping_list,
        assistant_reply
      } =
        apply_intent(
          intent,
          socket.assigns.shopping_list
        )

      {:noreply,
       socket
       |> assign(
         :messages,
         socket.assigns.messages ++
           [Message.new(:user, content), Message.new(:assistant, assistant_reply)]
       )
       |> assign(:shopping_list, shopping_list)
       |> assign_chat_form()}
    end
  end

  defp apply_intent(
         intent,
         shopping_list
       ) do
    case IntentHandler.handle(
           intent,
           shopping_list
         ) do
      {:ok, updated, message} ->
        {updated, message}

      {:compare, unchanged, message} ->
        {unchanged, message}

      {:error, unchanged, message} ->
        {unchanged, message}
    end
  end

  defp parse_quantity(value) do
    case Decimal.parse(value) do
      {quantity, ""} ->
        if Decimal.compare(quantity, 0) == :gt do
          {:ok, quantity}
        else
          {:error, :invalid_quantity}
        end

      _ ->
        {:error, :invalid_quantity}
    end
  end

  defp parse_unit(unit) do
    case unit do
      "each" -> {:ok, :each}
      "gram" -> {:ok, :gram}
      "kilogram" -> {:ok, :kilogram}
      "millilitre" -> {:ok, :millilitre}
      "litre" -> {:ok, :litre}
      _ -> {:error, :invalid_unit}
    end
  end

  defp format_unit(:each), do: " each"
  defp format_unit(:gram), do: " g"
  defp format_unit(:kilogram), do: " kg"
  defp format_unit(:millilitre), do: " ml"
  defp format_unit(:litre), do: " L"

  defp assign_item_form(socket, params \\ nil) do
    params =
      params ||
        %{
          "item_name" => "",
          "quantity" => "1",
          "unit" => "each"
        }

    assign(
      socket,
      :item_form,
      to_form(params, as: :shopping_item)
    )
  end

  defp assign_chat_form(socket, params \\ %{"message" => ""}) do
    assign(
      socket,
      :chat_form,
      to_form(params, as: :chat)
    )
  end

  defp handle_chat_command(
         "clear list",
         _shopping_list
       ) do
    {
      ShoppingList.new(),
      "Your shopping list has been cleared."
    }
  end

  defp handle_chat_command(
         _message,
         shopping_list
       ) do
    {
      shopping_list,
      "I received your message. Natural-language shopping commands are not enabled yet."
    }
  end
end
