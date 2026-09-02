defmodule DealAgent.Shopping.IntentParserTest do
  use ExUnit.Case, async: true

  alias DealAgent.Shopping.IntentParser

  test "parses add item" do
    intent =
      IntentParser.parse("add milk")

    assert intent.action == :add_item
    assert intent.item.name == "milk"
  end

  test "parses remove item" do
    intent =
      IntentParser.parse("remove bread")

    assert intent.action == :remove_item
    assert intent.item_name == "bread"
  end

  test "parses clear list" do
    assert IntentParser.parse("clear list").action == :clear_list
  end

  test "parses compare" do
    assert IntentParser.parse("compare supermarkets").action == :compare
  end

  test "returns unknown intent" do
    assert IntentParser.parse("what is the weather?").action == :unknown
  end
end
