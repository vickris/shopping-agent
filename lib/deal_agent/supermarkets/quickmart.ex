defmodule DealAgent.Supermarkets.Quickmart do
  @moduledoc "Quickmart adapter using the public Ruaka branch listing."
  @behaviour DealAgent.Supermarkets.Behaviour
  alias DealAgent.Shopping.{Product, SearchResult}
  alias DealAgent.Supermarkets.Quickmart.Client

  def name, do: :quickmart

  def search(item, opts \\ []) do
    client =
      Keyword.get(
        opts,
        :client,
        if(Keyword.has_key?(opts, :request_options), do: Client, else: __MODULE__.BrowserClient)
      )

    response =
      if client in [Client, __MODULE__.BrowserClient],
        do: client.search(item.name, opts),
        else: client.search(item.name)

    with {:ok, raw_products} <- response do
      products =
        Enum.map(raw_products, fn raw ->
          %Product{
            id: to_string(raw.id),
            name: raw.name,
            brand: raw.brand,
            price: raw.price,
            currency: :KES,
            quantity: raw.quantity,
            unit: raw.unit,
            supermarket: name(),
            url: raw.url,
            image_url: raw.image_url,
            in_stock: raw.in_stock,
            raw: raw
          }
        end)

      {:ok,
       %SearchResult{
         supermarket: name(),
         query: item.name,
         requested_item: item,
         products: products,
         metadata: %{count: length(products), branch: "Ruaka", branch_id: 1}
       }}
    end
  end
end
