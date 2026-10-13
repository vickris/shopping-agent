defmodule DealAgent.Shopping.MultiItemTest do
  use ExUnit.Case, async: true
  alias DealAgent.Shopping.{IntentConverter, IntentHandler, ShoppingList}
  alias DealAgent.Tools.CaptureIntent

  test "batch tool payload preserves order, amounts and compound names" do
    payload = %{
      action: "add_items",
      items: [
        %{name: "whole milk", quantity: "2", unit: "litre"},
        %{name: "baking soda", quantity: nil, unit: nil},
        %{name: "kiwi", quantity: nil, unit: nil}
      ]
    }

    assert {:ok, normalized} = CaptureIntent.execute(payload)
    assert {:ok, intent} = IntentConverter.convert(normalized, "shopping prose")
    assert Enum.map(intent.items, & &1.name) == ["whole milk", "baking soda", "kiwi"]
    refute hd(intent.items).quantity_unspecified
    assert Enum.at(intent.items, 1).quantity_unspecified
    assert {:ok, list, _} = IntentHandler.handle(intent, ShoppingList.new())
    assert length(list.items) == 3
    assert length(Enum.uniq_by(list.items, & &1.id)) == 3
  end

  test "invalid batches are rejected atomically instead of silently dropping items" do
    for items <- [
          [],
          nil,
          "milk",
          [%{name: "milk"}, %{name: "", quantity: "2"}],
          [%{name: "milk", quantity: "-1"}],
          List.duplicate(%{name: "milk"}, 31)
        ] do
      assert {:error, _} = IntentConverter.convert(%{action: "add_items", items: items}, "prose")
    end
  end
end
