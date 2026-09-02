defmodule TestLLM do
  @moduledoc """
  Deterministic `BeamAgent.LLM.Client` used in tests to drive the
  `DealAgent.Agents.ShoppingAgent` without a real model.

  It looks at the last message in the context and either emits a
  `:capture_intent` tool call (for a recognised command) or a final reply
  (after the tool has run, or when the command is not understood).
  """

  @behaviour BeamAgent.LLM.Client

  @number_words %{
    "a" => "1",
    "an" => "1",
    "one" => "1",
    "two" => "2",
    "three" => "3",
    "four" => "4",
    "five" => "5",
    "six" => "6"
  }

  @units %{
    "l" => :litre,
    "litre" => :litre,
    "litres" => :litre,
    "liter" => :litre,
    "liters" => :litre,
    "ml" => :millilitre,
    "millilitre" => :millilitre,
    "millilitres" => :millilitre,
    "g" => :gram,
    "gram" => :gram,
    "grams" => :gram,
    "kg" => :kilogram,
    "kilogram" => :kilogram,
    "kilograms" => :kilogram
  }

  @impl true
  def chat(messages, _opts) do
    case List.last(messages) do
      %{role: :tool} ->
        {:reply, "Done"}

      %{role: :user, content: content} when is_binary(content) ->
        interpret(content)

      _message ->
        {:reply, "I don't understand."}
    end
  end

  defp interpret(text) do
    case text |> String.downcase() |> String.split(~r/[^a-z0-9.]+/, trim: true) do
      ["add" | rest] -> capture_add(rest)
      ["remove" | rest] -> capture_remove(rest)
      ["clear" | _] -> tool_call(:capture_intent, %{action: "clear_list"})
      ["compare" | _] -> tool_call(:capture_intent, %{action: "compare"})
      _other -> {:reply, "I can't help with that."}
    end
  end

  defp capture_add(words) do
    {quantity, words} = take_quantity(words)
    {unit, words} = take_unit(words)

    name =
      words
      |> Enum.reject(&(&1 == "of"))
      |> Enum.join(" ")

    args =
      %{action: "add_item", name: name}
      |> maybe_put(:quantity, quantity)
      |> maybe_put(:unit, unit && Atom.to_string(unit))

    tool_call(:capture_intent, args)
  end

  defp capture_remove(words) do
    name = words |> Enum.reject(&(&1 == "of")) |> Enum.join(" ")
    tool_call(:capture_intent, %{action: "remove_item", name: name})
  end

  # A real provider returns a stable identifier for each tool call so the
  # follow-up tool result can be correlated back to it; the test client
  # just generates a unique one.
  defp tool_call(name, arguments) do
    {:tool_call,
     %{
       id: "test-call-" <> Integer.to_string(System.unique_integer([:positive])),
       name: name,
       arguments: arguments
     }}
  end

  defp take_quantity([word | rest]) when is_map_key(@number_words, word) do
    {Map.fetch!(@number_words, word), rest}
  end

  defp take_quantity([word | rest] = words) do
    if Regex.match?(~r/^\d+(\.\d+)?$/, word), do: {word, rest}, else: {nil, words}
  end

  defp take_quantity([]), do: {nil, []}

  defp take_unit([word | rest]) when is_map_key(@units, word) do
    {Map.fetch!(@units, word), rest}
  end

  defp take_unit(words), do: {nil, words}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
