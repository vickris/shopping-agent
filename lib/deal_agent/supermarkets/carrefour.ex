defmodule DealAgent.Supermarkets.Carrefour do
  @moduledoc """
  Carrefour supermarket adapter.

  The first version uses fixture data so the adapter boundary can be
  developed independently of live HTTP behaviour.
  """

  @behaviour DealAgent.Supermarkets.Behaviour

  alias DealAgent.Shopping.Product
  alias DealAgent.Shopping.SearchResult

  @impl true
  def name, do: :carrefour

  @impl true
  def search(item, opts \\ []) do
    client =
      Keyword.get(
        opts,
        :client,
        __MODULE__.Client
      )

    with {:ok, raw_products} <-
           client.search(item.name),
         {:ok, products} <-
           normalize_products(raw_products) do
      {:ok,
       %SearchResult{
         supermarket: name(),
         query: item.name,
         requested_item: item,
         products: products,
         metadata: %{
           count: length(products)
         }
       }}
    end
  end

  defp normalize_products(raw_products) do
    products =
      Enum.map(
        raw_products,
        &normalize_product/1
      )

    {:ok, products}
  end

  defp normalize_product(raw) do
    %Product{
      id: to_string(raw.id),
      name: raw.name,
      brand: raw.brand,
      price: Decimal.new(raw.price),
      currency: :KES,
      quantity: Decimal.new(raw.quantity),
      unit: raw.unit,
      supermarket: name(),
      url: raw.url,
      image_url: Map.get(raw, :image_url),
      in_stock: Map.get(raw, :in_stock, true),
      raw: raw
    }
  end
end
