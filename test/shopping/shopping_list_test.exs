defmodule DealAgent.Shopping.ShoppingListTest do
  use ExUnit.Case, async: true

  alias DealAgent.Shopping.Item
  alias DealAgent.Shopping.ShoppingList

  test "creates item with quantity and unit" do
    item =
      Item.new(
        "Milk",
        quantity: "2",
        unit: :litre
      )

    assert item.name == "Milk"
    assert Decimal.equal?(item.quantity, Decimal.new("2"))
    assert item.unit == :litre
  end

  test "updates an existing item" do
    item = Item.new("Milk")

    list =
      ShoppingList.new()
      |> ShoppingList.add_item(item)
      |> ShoppingList.update_item(
        item.id,
        %{
          quantity: Decimal.new("2"),
          unit: :litre
        }
      )

    updated = hd(list.items)

    assert Decimal.equal?(
             updated.quantity,
             Decimal.new("2")
           )

    assert updated.unit == :litre
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
