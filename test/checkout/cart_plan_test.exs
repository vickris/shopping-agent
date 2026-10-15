defmodule DealAgent.Checkout.CartPlanTest do
  use ExUnit.Case, async: true
  alias DealAgent.Checkout.CartPlan
  alias DealAgent.Shopping.{Item, Product, Selection}

  defp selection(item) do
    product = %Product{
      id: "43374",
      name: "Milk 500ml",
      price: Decimal.new("62"),
      currency: :KES,
      quantity: Decimal.new(500),
      unit: :millilitre,
      supermarket: :carrefour,
      url: "https://www.carrefour.ke/mafken/en/milk/p/43374",
      in_stock: true
    }

    {:ok, selection} = Selection.new(item, product)
    selection
  end

  test "aggregates repeat selections into one SKU and snapshots exact pack counts" do
    a = Item.new("milk", quantity: 1, unit: :litre)
    b = Item.new("milk", quantity: 500, unit: :millilitre)

    assert {:ok, plan} =
             CartPlan.build([a, b], %{a.id => selection(a), b.id => selection(b)}, :carrefour)

    assert [%{id: "43374", packs: 3, expected_price: "62"}] = plan.products
    assert plan.estimated_total == "186"
  end

  test "accepts store-specific selections and rejects cross-store baskets" do
    item = Item.new("milk")

    for {store, url} <- [
          {:quickmart, "https://www.quickmart.co.ke/milk-66"},
          {:naivas, "https://www.naivas.online/milk"}
        ] do
      selected = selection(item)
      selected = %{selected | product: %{selected.product | supermarket: store, url: url}}

      assert {:ok, %{store: name, products: [%{query: "milk"}]}} =
               CartPlan.build([item], %{item.id => selected}, store)

      assert name == Atom.to_string(store)

      assert {:error, :invalid_selection} =
               CartPlan.build([item], %{item.id => selected}, :carrefour)
    end
  end

  test "blocks incomplete, unsupported and external product URLs" do
    item = Item.new("milk")
    assert {:error, :empty_basket} = CartPlan.build([], %{}, :carrefour)
    assert {:error, :incomplete_basket} = CartPlan.build([item], %{}, :carrefour)
    assert {:error, :unsupported_store} = CartPlan.build([item], %{}, :unknown)
    selected = selection(item)
    bad_price = %{selected | product: %{selected.product | price: nil}}

    assert {:error, :invalid_selection} =
             CartPlan.build([item], %{item.id => bad_price}, :carrefour)

    forged = %{selected | product: %{selected.product | url: "https://example.com/p/43374"}}
    assert {:error, :invalid_selection} = CartPlan.build([item], %{item.id => forged}, :carrefour)
  end
end
