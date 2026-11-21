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

  test "React search reads product image IDs, selling prices and stock" do
    card = """
    <div class="group"><a href="/milk"><img src="https://cdn.example/product/2989/milk.jpg"></a>
    <span class="font-bold">KES <span>81</span></span><span class="line-through">KES 100</span>
    <p class="line-clamp-2">Milk 500Ml</p><button aria-label="Add to cart"></button></div>
    """

    assert {:ok, [product]} = ResponseParser.parse("<main>169 Result(s)" <> card <> "</main>")
    assert product.id == "2989"
    assert product.url == "https://www.naivas.online/milk"
    assert Decimal.equal?(product.price, "81")
    assert product.in_stock
    assert product.source.id_source == :product_image_path

    assert {:ok, [%{in_stock: false}]} =
             ResponseParser.parse(
               "<main>1 Result(s)" <>
                 String.replace(card, "aria-label=", "disabled aria-label=") <> "</main>"
             )

    assert {:ok, []} = ResponseParser.parse("<main>0 Result(s)</main>")
    assert {:error, _} = ResponseParser.parse("<main>1 Result(s)</main>")

    assert {:error, _} =
             ResponseParser.parse(
               "<main>1 Result(s)" <>
                 String.replace(card, "/product/2989/", "/unknown/") <> "</main>"
             )
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
             "https://www.naivas.online/search?q=milk+%26+cream"
  end
end
