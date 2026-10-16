defmodule DealAgent.Checkout.CartPlan do
  @moduledoc "Validated snapshot of a user-selected supermarket basket, including partial shopping lists."
  alias DealAgent.Shopping.Selection

  @stores [:carrefour, :quickmart, :naivas]

  def build(items, selections, store) when store in @stores and items != [] do
    lines = items |> Enum.map(&selections[&1.id]) |> Enum.reject(&is_nil/1)

    if lines == [] do
      {:error, :empty_basket}
    else
      valid = Enum.all?(lines, &valid_line?(&1, store))

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
          |> Enum.map(fn {id, group} ->
            first = hd(group)

            %{
              id: id,
              name: first.product.name,
              url: first.product.url,
              query:
                Map.get(first, :search_query) ||
                  Enum.find(items, fn item ->
                    selections[item.id] && selections[item.id].product.id == id
                  end).name,
              packs: Enum.sum(Enum.map(group, & &1.packs)),
              expected_price: Decimal.to_string(first.product.price, :normal)
            }
          end)

        if Enum.any?(products, &(&1.packs > 50)),
          do: {:error, :pack_limit},
          else:
            {:ok,
             %{
               store: Atom.to_string(store),
               selected_count: length(lines),
               skipped_count: length(items) - length(lines),
               products: products,
               estimated_total:
                 Decimal.to_string(Selection.total(items, selections).cost, :normal)
             }}
      else
        {:error, :invalid_selection}
      end
    end
  end

  def build([], _, store) when store in @stores, do: {:error, :empty_basket}
  def build(_, _, _), do: {:error, :unsupported_store}

  defp valid_line?(%{product: product, packs: packs}, store) do
    uri = URI.parse(product.url || "")

    product.supermarket == store and product.in_stock == true and product.currency == :KES and
      is_integer(packs) and packs > 0 and packs <= 50 and
      match?(%Decimal{}, product.price) and Decimal.compare(product.price, 0) != :lt and
      uri.scheme == "https" and uri.host in hosts(store) and
      uri.userinfo == nil and uri.port == 443 and
      valid_path?(uri.path || "", product.id, store)
  end

  defp hosts(:carrefour), do: ["www.carrefour.ke", "carrefour.ke"]
  defp hosts(:quickmart), do: ["www.quickmart.co.ke", "quickmart.co.ke"]
  defp hosts(:naivas), do: ["www.naivas.online", "naivas.online"]
  defp valid_path?(path, id, :carrefour), do: String.ends_with?(path, "/p/#{id}")

  defp valid_path?(path, _, _),
    do:
      path not in ["", "/"] and
        not Regex.match?(~r{^/(?:cart|checkout|customer|users|shops|login|register)(?:/|$)}, path)
end
