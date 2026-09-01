defmodule DealAgent.Shopping.IntentHandlerTest do
  use ExUnit.Case, async: true

  alias DealAgent.Shopping.Intent
  alias DealAgent.Shopping.IntentHandler
  alias DealAgent.Shopping.Item
  alias DealAgent.Shopping.ShoppingList

  test "adds an item" do
    item = Item.new("Milk")

    intent =
      Intent.add_item(
        item,
        "add milk"
      )

    assert {:ok, list, _message} =
             IntentHandler.handle(
               intent,
               ShoppingList.new()
             )

    assert ShoppingList.count(list) == 1
  end

  test "removes matching item" do
    milk = Item.new("Milk")

    list =
      ShoppingList.new()
      |> ShoppingList.add_item(milk)

    intent =
      Intent.remove_item(
        "milk",
        "remove milk"
      )

    assert {:ok, updated, _message} =
             IntentHandler.handle(
               intent,
               list
             )

    assert ShoppingList.empty?(updated)
  end

  test "does not modify list for unknown intent" do
    list = ShoppingList.new()

    assert {:error, ^list, _message} =
             IntentHandler.handle(
               Intent.unknown("hello"),
               list
             )
  end
end
