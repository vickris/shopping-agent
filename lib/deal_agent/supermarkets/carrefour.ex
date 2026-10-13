defmodule DealAgent.Supermarkets.Carrefour do
  @moduledoc """
  Carrefour supermarket adapter.

  Uses the headless browser scraper by default, with an injectable client
  for tests. Unknown pack sizes are preserved as nil rather than guessed.
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
        if(Keyword.has_key?(opts, :request_options),
          do: __MODULE__.Client,
          else: __MODULE__.BrowserClient
        )
      )

    with {:ok, raw_products} <-
           search_client(client, item.name, opts),
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

  defp search_client(__MODULE__.Client, query, opts) do
    __MODULE__.Client.search(
      query,
      Keyword.take(opts, [:request_options, :browser_fallback, :browser_client])
    )
  end

  defp search_client(__MODULE__.BrowserClient, query, opts),
    do: __MODULE__.BrowserClient.search(query, opts)

  defp search_client(client, query, _opts), do: client.search(query)

  defp decimal(nil), do: nil
  defp decimal(%Decimal{} = value), do: value
  defp decimal(value), do: Decimal.new(value)

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
      price: decimal(raw.price),
      currency: :KES,
      quantity: decimal(raw.quantity),
      unit: raw.unit,
      supermarket: name(),
      url: raw.url,
      image_url: Map.get(raw, :image_url),
      in_stock: Map.get(raw, :in_stock, true),
      raw: raw
    }
  end
end
