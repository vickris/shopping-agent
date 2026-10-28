defmodule DealAgent.Supermarkets.Foodplus.MockClient do
  def search("slow milk") do
    Process.sleep(100)
    search("milk")
  end

  def search("milk") do
    {:ok,
     [
       %{
         id: "701",
         name: "Foodplus Milk 500Ml",
         brand: nil,
         price: Decimal.new("70.00"),
         quantity: Decimal.new(500),
         unit: :millilitre,
         url: "https://foodplus.co.ke/foodplus-milk.html",
         image_url: nil,
         in_stock: true
       }
     ]}
  end

  def search("unreadable"), do: {:error, :unexpected_search_response}
  def search(_), do: {:ok, []}
end
