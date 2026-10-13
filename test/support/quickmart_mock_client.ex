defmodule DealAgent.Supermarkets.Quickmart.MockClient do
  def search("slow milk") do
    Process.sleep(100)
    search("milk")
  end

  def search("milk") do
    {:ok,
     [
       %{
         id: "quick-milk",
         name: "Quickmart Milk 500Ml",
         brand: nil,
         price: Decimal.new("65.00"),
         quantity: Decimal.new(500),
         unit: :millilitre,
         url: "https://example.test/quick-milk",
         image_url: nil,
         in_stock: true
       }
     ]}
  end

  def search("unreadable"), do: {:error, :unexpected_search_response}
  def search(_), do: {:ok, []}
end
