defmodule DealAgent.Shopping.Selection do
  @moduledoc "User-confirmed product and deterministic whole-pack costing."

  @units %{
    litre: {:volume, 1000},
    millilitre: {:volume, 1},
    kilogram: {:mass, 1000},
    gram: {:mass, 1},
    each: {:count, 1}
  }

  def new(item, product) do
    with true <- product.in_stock == true and product.currency == :KES,
         %Decimal{} <- product.price,
         true <- Decimal.compare(product.price, 0) != :lt,
         {:ok, packs} <- pack_count(item, product) do
      {:ok, %{product: product, packs: packs, cost: Decimal.mult(product.price, packs)}}
    else
      _ -> {:error, :incompatible_product}
    end
  end

  def resize(selection, packs) when is_integer(packs) and packs > 0 do
    %{selection | packs: packs, cost: Decimal.mult(selection.product.price, packs)}
  end

  def total(items, selections) do
    costs = for item <- items, selection = selections[item.id], do: selection.cost

    %{
      cost: Enum.reduce(costs, Decimal.new(0), &Decimal.add/2),
      unresolved: length(items) - length(costs)
    }
  end

  defp pack_count(%{quantity_unspecified: true}, _product), do: {:ok, 1}

  defp pack_count(%{unit: :each, quantity: amount}, _product), do: {:ok, ceil_packs(amount)}

  defp pack_count(_item, %{quantity: nil}), do: {:ok, 1}
  defp pack_count(_item, %{unit: nil}), do: {:ok, 1}

  defp pack_count(item, %{quantity: %Decimal{} = quantity, unit: unit}) do
    with {dimension, requested_factor} <- @units[item.unit],
         {^dimension, pack_factor} <- @units[unit],
         true <- Decimal.compare(quantity, 0) == :gt do
      {:ok,
       ceil_packs(
         Decimal.div(
           Decimal.mult(item.quantity, requested_factor),
           Decimal.mult(quantity, pack_factor)
         )
       )}
    else
      _ -> {:error, :unknown_or_incompatible_size}
    end
  end

  defp pack_count(_, _), do: {:error, :unknown_or_incompatible_size}
  defp ceil_packs(amount), do: amount |> Decimal.round(0, :ceiling) |> Decimal.to_integer()
end
