defmodule DealAgent.Supermarkets.FoodplusTest do
  use ExUnit.Case, async: true
  alias DealAgent.Supermarkets.Foodplus
  alias Foodplus.ResponseParser

  # Shape captured from Foodplus's public Magento search listing. No session
  # identifiers, form keys or customer data are retained in this fixture.
  defp card(name, price \\ "70", button \\ "<button class='tocart'>Add</button>") do
    """
    <li class="product-item"><div class="price-box" data-product-id="42">
      <span data-price-type="oldPrice" data-price-amount="99"></span>
      <span data-price-type="finalPrice" data-price-amount="#{price}">#{price} KSh</span>
    </div><a class="product-item-link" href="https://foodplus.co.ke/milk.html">#{name}</a>
    <img class="product-image-photo" src="https://foodplus.co.ke/media/milk.jpg">
    <form data-role="tocart-form" data-product-id="42">#{button}</form></li>
    """
  end

  defp page(cards),
    do:
      "<h1 class='page-title'>Search results for: 'milk'</h1><div class='products-grid'>#{cards}</div>"

  test "browser adapter normalizes final selling price and explicit title pack size" do
    html = page(card("FRESHA 500ML WHOLE MILK", "65.50"))
    runner = fn _, [_, "milk", "foodplus"], _ -> {Jason.encode!(%{html: html}), 0} end

    assert {:ok, result} =
             Foodplus.search(DealAgent.Shopping.Item.new("milk"),
               runner: runner,
               node_executable: "test-node"
             )

    assert [%{supermarket: :foodplus, in_stock: true} = product] = result.products
    assert Decimal.equal?(product.price, "65.50")
    assert Decimal.equal?(product.quantity, "500")
    assert product.unit == :millilitre
    assert product.url == "https://foodplus.co.ke/milk.html"
    refute result.metadata.checkout_supported
  end

  test "unavailable and unknown or ambiguous sizes remain explicit" do
    for name <- ["Milk", "Milk 2 x 500ML", "Milk 1L + 500ML", "Milk 2-5L"] do
      assert {:ok, [%{quantity: nil, unit: nil, in_stock: false}]} =
               ResponseParser.parse(page(card(name, "70", "<span>Out of stock</span>")))
    end

    for {name, quantity, unit} <- [
          {"Milk 2L", "2", :litre},
          {"Flour 2KG", "2", :kilogram},
          {"Eggs 6PCS", "6", :each}
        ] do
      assert {:ok, [product]} = ResponseParser.parse(page(card(name)))
      assert Decimal.equal?(product.quantity, quantity)
      assert product.unit == unit
    end
  end

  test "only explicit empty searches are empty; malformed or foreign cards fail" do
    assert {:ok, []} =
             ResponseParser.parse(
               page("<div class='message notice'>Your search returned no results.</div>")
             )

    for html <- [
          "",
          "<h1>Blocked</h1>",
          card("Milk 1L"),
          page(card("Milk 1L", "bad")),
          page(card("Milk 1L", "0")),
          page(
            String.replace(
              card("Milk 1L"),
              "https://foodplus.co.ke/milk.html",
              "https://example.com/milk.html"
            )
          )
        ] do
      assert {:error, _} = ResponseParser.parse(html)
    end

    assert Foodplus.Client.search_url("milk & cream") ==
             "https://foodplus.co.ke/catalogsearch/result/?q=milk+%26+cream"
  end
end
