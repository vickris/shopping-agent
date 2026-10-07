defmodule DealAgent.Supermarkets.CarrefourTest do
  use ExUnit.Case, async: true

  alias DealAgent.Shopping.Item
  alias DealAgent.Supermarkets.Carrefour
  alias DealAgent.Supermarkets.Carrefour.MockClient

  test "normalizes supermarket search results" do
    item =
      Item.new(
        "milk",
        quantity: "2",
        unit: :litre
      )

    assert {:ok, result} =
             Carrefour.search(
               item,
               client: MockClient
             )

    assert result.supermarket == :carrefour
    assert result.query == "milk"
    assert length(result.products) == 2

    [first | _] = result.products

    assert first.name ==
             "Brookside Whole Milk 1L"

    assert first.supermarket ==
             :carrefour

    assert Decimal.equal?(
             first.price,
             Decimal.new("189.00")
           )

    assert first.unit == :litre
  end
end
