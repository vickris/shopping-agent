defmodule DealAgent.Supermarkets.QuickmartClientTest do
  use ExUnit.Case, async: true
  alias DealAgent.Shopping.Item
  alias DealAgent.Supermarkets.Quickmart
  alias DealAgent.Supermarkets.Quickmart.{Client, ResponseParser}

  defp card(opts \\ []) do
    name = Keyword.get(opts, :name, "Fresha Fresh Whole Milk 500Ml")
    stock = Keyword.get(opts, :stock, "30")
    price = Keyword.get(opts, :price, "65.00")

    """
    <div class="products productInfoJs">
      <div class="products-img"><img src="https://cfn.quickmart.co.ke/milk.png"></div>
      <span class="products-price-new">KES #{price}</span><del>KES 100.00</del>
      <a class="products-title" href="/fresha-fresh-whole-milk-500ml-66">#{name}</a>
      <form><div class="quantity" data-stock="#{stock}"></div>
        <button name="btnAddToCart">Add</button><input name="selprod_id" value="802">
      </form>
    </div>
    """
  end

  defp listing(cards, count \\ "1"),
    do:
      "<div id='products-listing'>#{cards}</div><form id='frmProductSearchPaging'><input name='recordDisplayCount' value='#{count}'></form>"

  test "HTTP boundary uses branch-specific encoded query and normalizes products" do
    plug = fn conn ->
      assert conn.request_path == "/shops/products/1/keyword-milk%20%26%20cream"
      Plug.Conn.send_resp(conn, 200, listing(card()))
    end

    assert {:ok, result} =
             Quickmart.search(Item.new("milk & cream"), request_options: [plug: plug])

    assert result.metadata.branch == "Ruaka"

    assert [%{supermarket: :quickmart, currency: :KES, in_stock: true} = product] =
             result.products

    assert Decimal.equal?(product.price, "65.00")
    assert Decimal.equal?(product.quantity, "500")
    assert product.unit == :millilitre
    assert product.raw.source.size_source == :title
    assert product.url == "https://www.quickmart.co.ke/fresha-fresh-whole-milk-500ml-66"
  end

  test "zero stock and malformed cards are handled honestly" do
    assert {:ok, [%{in_stock: false}]} = ResponseParser.parse(listing(card(stock: "0")))

    assert {:error, {:invalid_product_card, _}} =
             ResponseParser.parse(listing(card(price: "unknown")))

    assert {:ok, [%{in_stock: false}]} = ResponseParser.parse(listing(card(stock: "unknown")))
  end

  test "only explicit empty listing is empty; home recommendations and blank pages fail" do
    assert {:ok, []} = ResponseParser.parse(listing("", "0"))
    assert {:error, :unexpected_search_response} = ResponseParser.parse(card())
    assert {:error, :unexpected_search_response} = ResponseParser.parse("<html></html>")
    assert {:error, :unexpected_search_response} = ResponseParser.parse(listing("", "1"))
  end

  test "title label parsing accepts Gms and preserves unknown bundles" do
    assert {:ok, [p]} = ResponseParser.parse(listing(card(name: "Flour 800Gms")))
    assert p.unit == :gram and Decimal.equal?(p.quantity, "800")

    for title <- ["Milk", "Milk 500Ml x 2", "Milk 500Ml + Bread 400G"] do
      assert {:ok, [%{quantity: nil, unit: nil}]} =
               ResponseParser.parse(listing(card(name: title)))
    end
  end

  test "deduplicates products and excludes prices from recommendations" do
    assert {:ok, [_]} = ResponseParser.parse(listing(card() <> card()) <> card(price: "999.00"))
  end

  test "HTTP failures and invalid queries do not become empty results" do
    plug = fn conn -> Plug.Conn.send_resp(conn, 429, "busy") end

    assert {:error, {:quickmart_http_error, 429}} =
             Client.search("milk", request_options: [plug: plug])

    assert {:error, :empty_query} = Client.search(" ")
    assert {:error, :invalid_query} = Client.search(nil)
  end
end
