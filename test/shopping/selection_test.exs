defmodule DealAgent.Shopping.SelectionTest do
  use ExUnit.Case, async: true
  alias DealAgent.Shopping.{Item, Selection}

  defp product(opts \\ []) do
    Map.merge(
      %{
        quantity: Decimal.new("500"),
        unit: :millilitre,
        price: Decimal.new("58.00"),
        currency: :KES,
        in_stock: true
      },
      Map.new(opts)
    )
  end

  test "converts compatible units and rounds to sufficient whole packs" do
    assert {:ok, %{packs: 4, cost: cost}} =
             Selection.new(Item.new("milk", quantity: 2, unit: :litre), product())

    assert Decimal.equal?(cost, "232.00")

    assert {:ok, %{packs: 3}} =
             Selection.new(
               Item.new("flour", quantity: "1.1", unit: :kilogram),
               product(unit: :gram)
             )

    assert {:ok, %{packs: 2}} =
             Selection.new(Item.new("milk", quantity: "750", unit: :millilitre), product())
  end

  test "each requests count packs even when labelled size is unknown" do
    assert {:ok, %{packs: 2}} =
             Selection.new(Item.new("milk", quantity: 2), product(quantity: nil, unit: nil))
  end

  test "unknown pack sizes can be selected for a measured request and adjusted" do
    item = Item.new("milk", quantity: 2, unit: :litre)

    for candidate <- [
          product(quantity: nil),
          product(unit: nil),
          product(quantity: nil, unit: nil)
        ] do
      assert {:ok, selection} = Selection.new(item, candidate)
      assert selection.packs == 1
      assert Decimal.equal?(selection.cost, "58")
      assert Decimal.equal?(Selection.resize(selection, 3).cost, "174")
      assert Selection.total([item], %{item.id => selection}).unresolved == 0
    end

    assert {:error, _} = Selection.new(item, product(quantity: nil, in_stock: false))
  end

  test "rejects unavailable, incompatible and zero-sized products" do
    item = Item.new("milk", quantity: 2, unit: :litre)

    for candidate <- [
          product(in_stock: false),
          product(unit: :gram),
          product(quantity: Decimal.new(0))
        ] do
      assert {:error, _} = Selection.new(item, candidate)
    end
  end

  test "sums only selections belonging to current rows" do
    a = Item.new("milk", quantity: 2, unit: :litre)
    b = Item.new("bread")
    {:ok, selection} = Selection.new(a, product())
    total = Selection.total([a, b], %{a.id => selection, "removed" => selection})
    assert Decimal.equal?(total.cost, "232.00")
    assert total.unresolved == 1
  end
end
