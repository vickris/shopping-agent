defmodule DealAgent.Supermarkets.Carrefour.MockClient do
  def search("milk") do
    {:ok,
     [
       %{
         id: "milk-1",
         name: "Brookside Whole Milk 1L",
         brand: "Brookside",
         price: "189.00",
         quantity: "1",
         unit: :litre,
         url: "https://example.test/milk-1",
         image_url: nil,
         in_stock: true
       },
       %{
         id: "milk-500",
         name: "Brookside Whole Milk 500ml",
         brand: "Brookside",
         price: "99.00",
         quantity: "500",
         unit: :millilitre,
         url: "https://example.test/milk-500",
         image_url: nil,
         in_stock: true
       }
     ]}
  end

  def search(_query) do
    {:ok, []}
  end
end
