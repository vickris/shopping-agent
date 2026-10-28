defmodule DealAgent.Shopping.IntentConverter do
  @moduledoc """
  Converts validated agent output into Shopping.Intent values.
  """

  alias DealAgent.Shopping.Intent
  alias DealAgent.Shopping.Item

  @spec convert(map(), String.t()) ::
          {:ok, Intent.t()}
          | {:error, term()}
  def convert(payload, raw_input) do
    with {:ok, supermarkets} <-
           DealAgent.Supermarkets.Registry.normalize(fetch(payload, :supermarkets)),
         {:ok, intent} <- convert_action(payload, raw_input) do
      {:ok, %{intent | supermarkets: supermarkets}}
    end
  end

  defp convert_action(payload, raw_input) do
    case fetch(payload, :action) do
      "add_items" ->
        convert_add_items(payload, raw_input)

      "add_item" ->
        convert_add_item(payload, raw_input)

      "remove_item" ->
        convert_remove_item(payload, raw_input)

      "clear_list" ->
        {:ok, Intent.clear_list(raw_input)}

      "list_supermarkets" ->
        {:ok, %Intent{action: :list_supermarkets, raw_input: raw_input}}

      "compare" ->
        {:ok, Intent.compare(raw_input)}

      nil ->
        {:error, :missing_action}

      action ->
        {:error, {:unsupported_action, action}}
    end
  end

  defp convert_add_items(payload, raw_input) do
    case fetch(payload, :items) do
      items when is_list(items) and length(items) in 1..30 ->
        Enum.reduce_while(items, {:ok, []}, fn
          payload, {:ok, acc} when is_map(payload) ->
            case convert_add_item(payload, raw_input) do
              {:ok, intent} -> {:cont, {:ok, [intent.item | acc]}}
              error -> {:halt, error}
            end

          _, _ ->
            {:halt, {:error, :invalid_items}}
        end)
        |> case do
          {:ok, items} -> {:ok, Intent.add_items(Enum.reverse(items), raw_input)}
          error -> error
        end

      _ ->
        {:error, :invalid_items}
    end
  end

  defp convert_add_item(payload, raw_input) do
    with {:ok, name} <- require_string(payload, :name),
         {:ok, quantity} <- parse_quantity(fetch(payload, :quantity)),
         {:ok, unit} <- parse_unit(fetch(payload, :unit)) do
      item =
        Item.new(
          name,
          quantity: quantity,
          quantity_unspecified: is_nil(fetch(payload, :quantity)),
          unit: unit
        )

      {:ok, Intent.add_item(item, raw_input)}
    end
  end

  defp convert_remove_item(payload, raw_input) do
    with {:ok, name} <- require_string(payload, :name) do
      {:ok, Intent.remove_item(name, raw_input)}
    end
  end

  defp require_string(payload, key) do
    case fetch(payload, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:invalid_field, key}}
          value -> {:ok, value}
        end

      _ ->
        {:error, {:invalid_field, key}}
    end
  end

  defp parse_quantity(nil) do
    {:ok, Decimal.new("1")}
  end

  defp parse_quantity(value)
       when is_binary(value) do
    case Decimal.parse(value) do
      {quantity, ""} ->
        if Decimal.compare(quantity, 0) == :gt do
          {:ok, quantity}
        else
          {:error, :invalid_quantity}
        end

      _ ->
        {:error, :invalid_quantity}
    end
  end

  defp parse_quantity(value)
       when is_integer(value) do
    parse_quantity(Integer.to_string(value))
  end

  defp parse_quantity(_value) do
    {:error, :invalid_quantity}
  end

  defp parse_unit(nil), do: {:ok, :each}

  defp parse_unit(unit) do
    case to_string(unit) do
      "each" -> {:ok, :each}
      "gram" -> {:ok, :gram}
      "kilogram" -> {:ok, :kilogram}
      "millilitre" -> {:ok, :millilitre}
      "litre" -> {:ok, :litre}
      value -> {:error, {:invalid_unit, value}}
    end
  end

  defp fetch(map, key) do
    Map.get(map, key) ||
      Map.get(map, Atom.to_string(key))
  end
end
