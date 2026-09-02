defmodule DealAgent.Agents.ShoppingAgentTest do
  use ExUnit.Case, async: true

  alias DealAgent.Agents.ShoppingAgent
  alias DealAgent.Shopping.Intent

  test "interprets a simple add item command" do
    input = "Add two litres of milk"

    assert {:ok, %Intent{action: :add_item} = intent} =
             ShoppingAgent.interpret(input, llm: {TestLLM, []})

    assert intent.item.name == "milk"

    assert Decimal.equal?(
             intent.item.quantity,
             Decimal.new("2")
           )

    assert intent.item.unit == :litre
  end

  test "interprets a simple remove item command" do
    input = "remove milk"

    assert {:ok, %Intent{action: :remove_item}} =
             ShoppingAgent.interpret(input, llm: {TestLLM, []})
  end

  test "returns an error for unrecognized commands" do
    input = "hello world"

    assert {:error, :intent_not_captured} =
             ShoppingAgent.interpret(input, llm: {TestLLM, []})
  end
end
