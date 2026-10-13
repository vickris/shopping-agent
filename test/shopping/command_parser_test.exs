defmodule DealAgent.Shopping.CommandParserTest do
  use ExUnit.Case, async: true
  alias DealAgent.Shopping.CommandParser

  test "preserves qualifiers and converts explicit quantity and unit" do
    assert {:ok, intent} = CommandParser.parse("Add two litres of Brookside whole milk")
    assert intent.item.name == "Brookside whole milk"
    assert intent.item.unit == :litre
    assert Decimal.equal?(intent.item.quantity, "2")
    assert {:ok, intent} = CommandParser.parse("0.5 kg of sugar")
    assert intent.item.unit == :kilogram
    assert Decimal.equal?(intent.item.quantity, "0.5")
  end

  test "does not guess ambiguous or multiple-item requests" do
    for input <- [
          "milk",
          "2 litres of milk and bread",
          "2 litres of milk, 1 loaf",
          "0 litres of milk",
          "2 litres",
          "compare",
          "remove 2 litres of milk"
        ] do
      assert {:error, _} = CommandParser.parse(input)
    end
  end
end
