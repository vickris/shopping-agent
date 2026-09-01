defmodule DealAgent.Shopping.IntentHandler do
  @moduledoc """
  Applies structured shopping intents to deterministic domain state.
  """

  alias DealAgent.Shopping.Intent
  alias DealAgent.Shopping.ShoppingList

  @type result ::
          {:ok, ShoppingList.t(), String.t()}
          | {:compare, ShoppingList.t(), String.t()}
          | {:error, ShoppingList.t(), String.t()}

  @spec handle(Intent.t(), ShoppingList.t()) :: result()
  def handle(
        %Intent{
          action: :add_item,
          item: item
        },
        shopping_list
      ) do
    updated =
      ShoppingList.add_item(
        shopping_list,
        item
      )

    {:ok, updated, "Added #{item.name} to your shopping list."}
  end

  def handle(
        %Intent{
          action: :remove_item,
          item_name: item_name
        },
        shopping_list
      ) do
    case find_item_by_name(
           shopping_list,
           item_name
         ) do
      nil ->
        {:error, shopping_list, "I couldn't find #{item_name} on your shopping list."}

      item ->
        updated =
          ShoppingList.remove_item(
            shopping_list,
            item.id
          )

        {:ok, updated, "Removed #{item.name} from your shopping list."}
    end
  end

  def handle(
        %Intent{action: :clear_list},
        shopping_list
      ) do
    {:ok, ShoppingList.clear(shopping_list), "Your shopping list has been cleared."}
  end

  def handle(
        %Intent{action: :compare},
        shopping_list
      ) do
    {:compare, shopping_list, "Ready to compare supermarkets."}
  end

  def handle(
        %Intent{action: :unknown},
        shopping_list
      ) do
    {:error, shopping_list, "I don't understand that shopping command yet."}
  end

  defp find_item_by_name(shopping_list, name) do
    target = normalize(name)

    Enum.find(
      shopping_list.items,
      fn item ->
        normalize(item.name) == target
      end
    )
  end

  defp normalize(value) do
    value
    |> String.trim()
    |> String.downcase()
  end
end
