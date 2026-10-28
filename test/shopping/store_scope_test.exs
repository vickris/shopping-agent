defmodule DealAgent.Shopping.StoreScopeTest do
  use ExUnit.Case, async: true
  alias DealAgent.Shopping.IntentConverter

  test "store names are normalized without silently widening the comparison" do
    assert {:ok, %{supermarkets: ["naivas", "carrefour", "foodplus"]}} =
             IntentConverter.convert(
               %{
                 action: "compare",
                 supermarkets: ["Naivas", " CARREFOUR ", "Chandarana", "Naivas"]
               },
               ""
             )

    assert {:ok, %{supermarkets: nil}} = IntentConverter.convert(%{action: "compare"}, "")

    for stores <- [[], ["tesco"], [123], "naivas"] do
      assert {:error, :unsupported_supermarkets} =
               IntentConverter.convert(%{action: "compare", supermarkets: stores}, "")
    end
  end

  test "the existing intent tool preserves store scope and remains the only registered tool" do
    assert %{capture_intent: DealAgent.Tools.CaptureIntent} == DealAgent.Tools.Registry.tools()

    assert {:ok, %{supermarkets: ["naivas", "carrefour"]}} =
             DealAgent.Tools.CaptureIntent.execute(%{
               "action" => "compare",
               "supermarkets" => ["naivas", "carrefour"]
             })

    assert {:error, :unsupported_command} =
             DealAgent.Shopping.CommandParser.parse("2 litres of milk from Naivas")
  end
end
