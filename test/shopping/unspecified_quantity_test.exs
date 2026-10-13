defmodule DealAgent.Shopping.UnspecifiedQuantityTest do
  use ExUnit.Case, async: true
  alias DealAgent.Shopping.{IntentConverter, Selection, Product}

  test "missing quantity is explicit and selection defaults to one adjustable pack" do
    assert {:ok, intent} =
             IntentConverter.convert(
               %{action: "add_item", name: "milk", quantity: nil, unit: nil},
               "milk"
             )

    item = intent.item
    assert item.quantity_unspecified

    product = %Product{
      id: "milk",
      name: "Milk",
      supermarket: :naivas,
      price: Decimal.new("100"),
      currency: :KES,
      in_stock: true,
      quantity: nil,
      unit: nil
    }

    assert {:ok, selection} = Selection.new(item, product)
    assert selection.packs == 1
    assert Decimal.equal?(selection.cost, "100")
    assert Decimal.equal?(Selection.resize(selection, 3).cost, "300")
  end

  test "explicit amounts still calculate packs without the unspecified flag" do
    assert {:ok, intent} =
             IntentConverter.convert(
               %{action: "add_item", name: "milk", quantity: "2", unit: "litre"},
               "2 litres of milk"
             )

    refute intent.item.quantity_unspecified
  end
end
