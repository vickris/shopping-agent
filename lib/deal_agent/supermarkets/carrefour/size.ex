defmodule DealAgent.Supermarkets.Carrefour.Size do
  @moduledoc """
  Parses labelled pack contents without inferring sizes from product names.

  Multipacks return total contents in the label's unit. Unknown sizes return nil
  fields; treating them as a guessed size would make later comparisons unsafe.
  """

  @number ~r/^\d+(?:\.\d+)?$/
  @units %{
    "ml" => :millilitre,
    "l" => :litre,
    "g" => :gram,
    "gm" => :gram,
    "kg" => :kilogram,
    "piece" => :each,
    "pieces" => :each,
    "pc" => :each,
    "pcs" => :each
  }

  def parse(label) when is_binary(label) do
    label = label |> String.trim() |> String.downcase() |> String.replace("×", "x")

    cond do
      match =
          Regex.run(~r/^(\d+(?:\.\d+)?)\s*(ml|kg|gm|g|l)\s*x\s*(\d+)\s*(?:pieces?|pcs?)?$/, label) ->
        [_, amount, unit, count] = match
        result(amount, unit, count)

      match = Regex.run(~r/^(\d+)\s*x\s*(\d+(?:\.\d+)?)\s*(ml|kg|gm|g|l)$/, label) ->
        [_, count, amount, unit] = match
        result(amount, unit, count)

      match =
          Regex.run(~r/^(\d+(?:\.\d+)?)\s*(ml|kg|gm|g|l|pieces?|pcs?)(?:\s+of\s+eggs)?$/, label) ->
        [_, amount, unit] = match
        result(amount, unit, "1")

      true ->
        {nil, nil}
    end
  end

  def parse(_label), do: {nil, nil}

  defp result(amount, unit, count) do
    if Regex.match?(@number, amount) do
      quantity = Decimal.mult(Decimal.new(amount), Decimal.new(count))

      if Decimal.compare(quantity, 0) == :gt,
        do: {quantity, Map.fetch!(@units, unit)},
        else: {nil, nil}
    else
      {nil, nil}
    end
  end
end
