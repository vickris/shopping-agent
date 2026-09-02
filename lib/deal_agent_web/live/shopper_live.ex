defmodule DealAgentWeb.ShopperLive do
  use DealAgentWeb, :live_view

  alias DealAgent.Agents.ShoppingAgent
  alias DealAgent.Chat.Message
  alias DealAgent.Shopping.IntentHandler
  alias DealAgent.Shopping.Item
  alias DealAgent.Shopping.ShoppingList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:shopping_list, ShoppingList.new())
     |> assign(:units, Item.units())
     |> assign(:messages, [])
     |> assign(:agent_status, :idle)
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

    cond do
      content == "" ->
        {:noreply, socket}

      command = chat_command(content) ->
        {:noreply, run_chat_command(socket, content, command)}

      true ->
        user_message =
          Message.new(:user, content)

        messages =
          socket.assigns.messages ++
            [user_message]

        socket =
          socket
          |> assign(
            :messages,
            messages
          )
          |> assign(:agent_status, :thinking)
          |> assign_chat_form()

        {:noreply,
         start_async(
           socket,
           {:interpret_message, user_message.id},
           fn ->
             ShoppingAgent.interpret(content)
           end
         )}
    end
  end

  @impl true
  def handle_async(
        {:interpret_message, _message_id},
        {:ok, {:ok, intent}},
        socket
      ) do
    {:noreply, apply_shopping_intent(socket, intent)}
  end

  def handle_async(
        {:interpret_message, _message_id},
        {:ok, {:error, reason}},
        socket
      ) do
    {:noreply,
     socket
     |> append_assistant_message(agent_error_message(reason))
     |> assign(:agent_status, :idle)}
  end

  def handle_async(
        {:interpret_message, _message_id},
        {:exit, reason},
        socket
      ) do
    require Logger

    Logger.error("Shopping agent async task failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> append_assistant_message("Something went wrong while processing your request.")
     |> assign(:agent_status, :idle)}
  end

  defp agent_error_message(_reason) do
    "I couldn't understand that shopping request. Please try rephrasing it."
  end

  defp append_assistant_message(socket, content) do
    assistant_message =
      Message.new(:assistant, content)

    messages =
      socket.assigns.messages ++
        [assistant_message]

    assign(socket, :messages, messages)
  end

  defp apply_shopping_intent(
         socket,
         intent
       ) do
    case IntentHandler.handle(
           intent,
           socket.assigns.shopping_list
         ) do
      {:ok, shopping_list, reply} ->
        socket
        |> assign(:shopping_list, shopping_list)
        |> append_assistant_message(reply)
        |> assign(:agent_status, :idle)

      {:compare, shopping_list, reply} ->
        socket
        |> assign(:shopping_list, shopping_list)
        |> append_assistant_message(reply)
        |> assign(:agent_status, :idle)

      {:error, shopping_list, reply} ->
        socket
        |> assign(:shopping_list, shopping_list)
        |> append_assistant_message(reply)
        |> assign(:agent_status, :idle)
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

  # Commands handled locally, without a round-trip through the agent/LLM.
  defp chat_command(content) do
    case String.downcase(content) do
      "clear list" -> :clear_list
      _ -> nil
    end
  end

  defp run_chat_command(socket, content, :clear_list) do
    user_message = Message.new(:user, content)

    socket
    |> assign(:messages, socket.assigns.messages ++ [user_message])
    |> assign(:shopping_list, ShoppingList.new())
    |> append_assistant_message("Your shopping list has been cleared.")
    |> assign(:agent_status, :idle)
    |> assign_chat_form()
  end
end
