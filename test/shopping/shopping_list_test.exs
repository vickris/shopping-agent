defmodule DealAgent.Shopping.ShoppingListTest do
  use ExUnit.Case, async: true

  alias DealAgent.Shopping.Item
  alias DealAgent.Shopping.ShoppingList

  test "adds an item" do
    item = Item.new("Milk")

    list =
      ShoppingList.new()
      |> ShoppingList.add_item(item)

    assert ShoppingList.count(list) == 1
    assert hd(list.items).name == "Milk"
  end

  test "removes an item by id" do
    milk = Item.new("Milk")
    bread = Item.new("Bread")

    list =
      ShoppingList.new()
      |> ShoppingList.add_item(milk)
      |> ShoppingList.add_item(bread)
      |> ShoppingList.remove_item(milk.id)

    assert ShoppingList.count(list) == 1
    assert hd(list.items).name == "Bread"
  end

  test "is empty initially" do
    assert ShoppingList.empty?(ShoppingList.new())
  end
end
