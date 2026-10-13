defmodule DealAgent.Checkout.CartPlan do
  @moduledoc "Validated snapshot of a complete, user-selected Carrefour basket."
  alias DealAgent.Shopping.Selection

  def build(items, selections, :carrefour) when items != [] do
    if Selection.total(items, selections).unresolved != 0 do
      {:error, :incomplete_basket}
    else
      lines = Enum.map(items, &selections[&1.id])

      valid = Enum.all?(lines, &valid_line?/1)

      prices_consistent =
        valid and
          lines
          |> Enum.group_by(& &1.product.id)
          |> Enum.all?(fn {_, group} ->
            Enum.all?(group, &Decimal.equal?(&1.product.price, hd(group).product.price))
          end)

      if valid and prices_consistent do
        products =
          lines
          |> Enum.group_by(& &1.product.id)
          |> Enum.map(fn {id, selections} ->
            first = hd(selections)

            %{
              id: id,
              name: first.product.name,
              url: first.product.url,
              query: first.product.name,
              packs: Enum.sum(Enum.map(selections, & &1.packs)),
              expected_price: Decimal.to_string(first.product.price, :normal)
            }
          end)

        if Enum.any?(products, &(&1.packs > 50)),
          do: {:error, :pack_limit},
          else:
            {:ok,
             %{
               store: "carrefour",
               products: products,
               estimated_total:
                 Decimal.to_string(Selection.total(items, selections).cost, :normal)
             }}
      else
        {:error, :invalid_selection}
      end
    end
  end

  def build([], _, :carrefour), do: {:error, :empty_basket}
  def build(_, _, _), do: {:error, :unsupported_store}

  defp valid_line?(%{product: product, packs: packs}) do
    uri = URI.parse(product.url || "")

    product.supermarket == :carrefour and product.in_stock == true and product.currency == :KES and
      is_integer(packs) and packs > 0 and packs <= 50 and
      match?(%Decimal{}, product.price) and Decimal.compare(product.price, 0) != :lt and
      uri.scheme == "https" and uri.host in ["www.carrefour.ke", "carrefour.ke"] and
      uri.userinfo == nil and uri.port == 443 and
      String.ends_with?(uri.path || "", "/p/#{product.id}")
  end
end
