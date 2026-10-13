defmodule DealAgent.Supermarkets.NaivasTest do
  use ExUnit.Case, async: true
  alias DealAgent.Supermarkets.Naivas
  alias Naivas.ResponseParser

  defp card(name, price \\ "329", extra \\ "") do
    """
    <div class="border-naivas-bg">
      <a title="#{name}" href="https://www.naivas.online/milk"><span class="line-clamp-2">#{name}</span></a>
      <div class="product-price"><span class="font-bold">KES&nbsp;#{price}</span><span class="line-through">KES 400</span></div>
      <form><input name="product_id" value="42"><button #{extra}>ADD TO CART</button></form>
    </div>
    """
  end

  defp page(card), do: "<h2>1 Search Results Found</h2>" <> card

  test "browser adapter routes Naivas and normalizes selling price and litres" do
    html = page(card("Bio Fresh Whole Milk 2 L"))
    runner = fn _, [_, "milk", "naivas"], _ -> {Jason.encode!(%{html: html}), 0} end

    assert {:ok, result} =
             Naivas.search(DealAgent.Shopping.Item.new("milk"),
               runner: runner,
               node_executable: "node-test"
             )

    assert [%{supermarket: :naivas, in_stock: true} = product] = result.products
    assert Decimal.equal?(product.price, "329")
    assert Decimal.equal?(product.quantity, "2")
    assert product.unit == :litre
  end

  test "title spellings and ambiguous ranges preserve size semantics" do
    for {title, amount, unit} <- [
          {"Milk 1Ltr", "1", :litre},
          {"Milk 500Ml", "500", :millilitre},
          {"Powder 400Gm", "400", :gram}
        ] do
      assert {:ok, [product]} = ResponseParser.parse(page(card(title, "1,299.50", "disabled")))
      assert Decimal.equal?(product.price, "1299.50")
      assert Decimal.equal?(product.quantity, amount)
      assert product.unit == unit
      refute product.in_stock
    end

    for title <- ["Powder 2-5Kg", "Milk 2 x 500Ml", "Milk 1L + 500Ml", "Milk"] do
      assert {:ok, [%{quantity: nil, unit: nil}]} = ResponseParser.parse(page(card(title)))
    end
  end

  test "blank, blocked, invalid cards and homepage recommendations are not empty results" do
    assert {:ok, []} = ResponseParser.parse("<h2>0 Search Results Found</h2>")

    for html <- [
          "<html></html>",
          "<h1>Sorry, you have been blocked</h1>",
          card("Milk 1L"),
          page(card("Milk 1L", "bad"))
        ] do
      assert {:error, _} = ResponseParser.parse(html)
    end

    assert Naivas.Client.search_url("milk & cream") ==
             "https://www.naivas.online/search?term=milk+%26+cream"
  end
end
