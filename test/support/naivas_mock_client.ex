defmodule DealAgent.Supermarkets.Naivas.MockClient do
  def search("slow milk") do
    Process.sleep(100)
    search("milk")
  end

  def search("milk") do
    {:ok,
     [
       %{
         id: "naivas-milk",
         name: "Naivas Milk 500Ml",
         brand: nil,
         price: Decimal.new("70.00"),
         quantity: Decimal.new(500),
         unit: :millilitre,
         url: "https://example.test/naivas-milk",
         image_url: nil,
         in_stock: true
       }
     ]}
  end

  def search("unreadable"), do: {:error, :unexpected_search_response}
  def search(_), do: {:ok, []}
end
