defmodule DealAgent.Shopping.IntentParser do
  @moduledoc """
  Deterministically parses a small subset of shopping commands.

  This exists to establish the intent pipeline before introducing an LLM.
  """

  alias DealAgent.Shopping.Intent
  alias DealAgent.Shopping.Item

  @spec parse(String.t()) :: Intent.t()
  def parse(input) when is_binary(input) do
    normalized =
      input
      |> String.trim()
      |> String.downcase()

    cond do
      normalized == "clear list" ->
        Intent.clear_list(input)

      normalized in [
        "compare",
        "compare prices",
        "compare supermarkets"
      ] ->
        Intent.compare(input)

      String.starts_with?(normalized, "add ") ->
        parse_add(input)

      String.starts_with?(normalized, "remove ") ->
        parse_remove(input)

      true ->
        Intent.unknown(input)
    end
  end

  defp parse_add(input) do
    item_name =
      input
      |> String.trim()
      |> String.replace_prefix("add ", "")
      |> String.trim()

    case item_name do
      "" ->
        Intent.unknown(input)

      name ->
        item =
          Item.new(
            name,
            quantity: 1,
            unit: :each
          )

        Intent.add_item(item, input)
    end
  end

  defp parse_remove(input) do
    item_name =
      input
      |> String.trim()
      |> String.replace_prefix("remove ", "")
      |> String.trim()

    case item_name do
      "" ->
        Intent.unknown(input)

      name ->
        Intent.remove_item(name, input)
    end
  end
end
