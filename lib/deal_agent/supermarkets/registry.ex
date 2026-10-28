defmodule DealAgent.Supermarkets.Registry do
  @moduledoc """
  Registry of supermarkets available to the Deal Agent.
  """

  @supermarkets %{
    carrefour: DealAgent.Supermarkets.Carrefour,
    quickmart: DealAgent.Supermarkets.Quickmart,
    naivas: DealAgent.Supermarkets.Naivas,
    foodplus: DealAgent.Supermarkets.Foodplus
  }

  @labels %{
    "carrefour" => "Carrefour",
    "quickmart" => "Quickmart",
    "naivas" => "Naivas",
    "foodplus" => "Foodplus"
  }
  def ids, do: ~w(carrefour quickmart naivas foodplus)
  def labels, do: Enum.map_join(ids(), ", ", &Map.fetch!(@labels, &1))

  def normalize(nil), do: {:ok, nil}

  def normalize(names) when is_list(names) and length(names) in 1..4 do
    names =
      Enum.map(names, fn
        name when is_binary(name) ->
          case name |> String.downcase() |> String.trim() do
            name when name in ["chandarana", "chandarana foodplus", "food plus"] -> "foodplus"
            name -> name
          end

        _ ->
          nil
      end)

    if Enum.all?(names, &(&1 in ids())),
      do: {:ok, Enum.uniq(names)},
      else: {:error, :unsupported_supermarkets}
  end

  def normalize(_), do: {:error, :unsupported_supermarkets}

  def fetch(name) do
    Map.fetch(@supermarkets, name)
  end

  def all do
    Map.values(@supermarkets)
  end
end
