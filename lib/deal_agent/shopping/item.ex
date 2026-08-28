defmodule DealAgent.Shopping.Item do
  @moduledoc """
  Represents one requested shopping item.
  """

  @enforce_keys [:id, :name, :quantity, :unit]

  defstruct [
    :id,
    :name,
    :quantity,
    :unit,
    :notes
  ]

  @type unit ::
          :each
          | :gram
          | :kilogram
          | :millilitre
          | :litre

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          quantity: Decimal.t(),
          unit: unit(),
          notes: String.t() | nil
        }

  @units [
    {"Each", :each},
    {"Grams", :gram},
    {"Kilograms", :kilogram},
    {"Millilitres", :millilitre},
    {"Litres", :litre}
  ]

  def units, do: @units

  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      name: normalize_name(name),
      quantity: normalize_quantity(Keyword.get(opts, :quantity, 1)),
      unit: Keyword.get(opts, :unit, :each),
      notes: Keyword.get(opts, :notes)
    }
  end

  defp normalize_name(name) do
    name
    |> String.trim()
  end

  defp normalize_quantity(%Decimal{} = quantity), do: quantity
  defp normalize_quantity(quantity) when is_integer(quantity), do: Decimal.new(quantity)
  defp normalize_quantity(quantity) when is_binary(quantity), do: Decimal.new(quantity)

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end
