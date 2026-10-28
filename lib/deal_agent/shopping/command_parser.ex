defmodule DealAgent.Shopping.CommandParser do
  @moduledoc "Conservative single-item fallback for a temporarily unavailable LLM."
  alias DealAgent.Shopping.IntentConverter

  @numbers %{
    "one" => "1",
    "two" => "2",
    "three" => "3",
    "four" => "4",
    "five" => "5",
    "six" => "6",
    "seven" => "7",
    "eight" => "8",
    "nine" => "9",
    "ten" => "10"
  }
  @units %{
    "l" => "litre",
    "litre" => "litre",
    "litres" => "litre",
    "liter" => "litre",
    "liters" => "litre",
    "ml" => "millilitre",
    "millilitre" => "millilitre",
    "millilitres" => "millilitre",
    "g" => "gram",
    "gram" => "gram",
    "grams" => "gram",
    "kg" => "kilogram",
    "kilogram" => "kilogram",
    "kilograms" => "kilogram",
    "each" => "each"
  }

  def parse(input) do
    case Regex.run(
           ~r/^(?:add\s+)?(\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten)\s*(litres?|liters?|millilitres?|kilograms?|grams?|each|ml|kg|l|g)\s+(?:of\s+)?(.+)$/i,
           String.trim(input)
         ) do
      [_, amount, unit, name] ->
        if Regex.match?(
             ~r/[,;\n]|\b(?:and|or|then|compare|from|at|carrefour|quickmart|naivas|foodplus|chandarana)\b/i,
             name
           ) do
          {:error, :unsupported_command}
        else
          IntentConverter.convert(
            %{
              action: "add_item",
              name: String.trim(name),
              quantity: Map.get(@numbers, String.downcase(amount), amount),
              unit: @units[String.downcase(unit)]
            },
            input
          )
        end

      _ ->
        {:error, :unsupported_command}
    end
  end
end
