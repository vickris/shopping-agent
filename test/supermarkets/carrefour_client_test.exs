defmodule DealAgent.Supermarkets.CarrefourClientTest do
  use ExUnit.Case, async: true

  alias DealAgent.Shopping.Item
  alias DealAgent.Supermarkets.Carrefour
  alias DealAgent.Supermarkets.Carrefour.Client
  alias DealAgent.Supermarkets.Carrefour.ResponseParser
  alias DealAgent.Supermarkets.Carrefour.Size

  defmodule TimeoutAdapter do
    def run(request), do: {request, %Req.TransportError{reason: :timeout}}
  end

  # Reduced from the live Carrefour Kenya milk-search cards (2026-10-08).
  # Keep the actual selectors and nesting while excluding decorative elements.
  defp card(opts \\ []) do
    name = Keyword.get(opts, :name, "Carrefour UHT Whole milk 500ml")
    size = Keyword.get(opts, :size, "500ml")
    price = Keyword.get(opts, :price, "58.00")
    disabled = Keyword.get(opts, :disabled, "")

    """
    <div class="relative flex flex-col group">
      <div><a href="/mafken/en/uht-milk-full-fat/milk/p/247170?sid=SLOTTED">
        <img alt="Product image" src="https://cdn.mafrservices.com/milk.jpg">
      </a><button aria-label="Add to cart" #{disabled}></button></div>
      <a href="/mafken/en/uht-milk-full-fat/milk/p/247170?sid=SLOTTED">
        <span class="font-medium line-clamp-2">#{name}</span>
      </a>
      <div class="flex flex-wrap items-baseline">
        <span>KES</span><span>#{price}</span><span class="line-through">99.00</span>
      </div>
      <span class="text-xs line-clamp-1"><span></span><span><span>#{size}</span></span></span>
      <div><span>Tod. 6:00 PM</span></div>
    </div>
    """
  end

  test "HTTP search encodes query parameters and returns normalized domain products" do
    html = card()

    plug = fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.request_path == "/mafken/en/search"
      assert conn.query_params == %{"keyword" => "milk & cream"}
      Plug.Conn.send_resp(conn, 200, html)
    end

    assert {:ok, result} =
             Carrefour.search(Item.new("milk & cream"), request_options: [plug: plug])

    assert result.requested_item.name == "milk & cream"
    assert result.metadata.count == 1
    assert [product] = result.products
    assert product.id == "247170"
    assert product.currency == :KES
    assert product.supermarket == :carrefour
    assert Decimal.equal?(product.price, Decimal.new("58.00"))
    assert Decimal.equal?(product.quantity, Decimal.new("500"))
    assert product.unit == :millilitre
    assert product.in_stock
    assert product.brand == nil

    assert product.url ==
             "https://www.carrefour.ke/mafken/en/uht-milk-full-fat/milk/p/247170?sid=SLOTTED"

    assert product.image_url == "https://cdn.mafrservices.com/milk.jpg"
    assert product.raw.source.size_label == "500ml"
  end

  test "parses pack price with thousands separators and total multipack contents" do
    assert {:ok, [product]} =
             ResponseParser.parse(card(price: "1,597.00", size: "250ml x 6 Pieces"))

    assert Decimal.equal?(product.price, Decimal.new("1597.00"))
    assert Decimal.equal?(product.quantity, Decimal.new("1500"))
    assert product.unit == :millilitre
  end

  test "unknown sizes remain unknown, including mixed bundles" do
    for label <- ["", "450g + 2 x 1l", "Large", "0ml"] do
      assert {:ok, [product]} = ResponseParser.parse(card(size: label))
      assert product.quantity == nil
      assert product.unit == nil
      assert product.source.size_status == :unknown
    end
  end

  test "normalizes supported size labels without floats" do
    for {label, amount, unit} <- [
          {"1L", "1", :litre},
          {"0.5 kg", "0.5", :kilogram},
          {"500Gm", "500", :gram},
          {"6 x 250ml", "1500", :millilitre},
          {"30 Pieces", "30", :each},
          {"12 Pieces of Eggs", "12", :each}
        ] do
      assert {quantity, ^unit} = Size.parse(label)
      assert Decimal.equal?(quantity, Decimal.new(amount))
    end
  end

  test "disabled and missing cart buttons do not imply availability" do
    assert {:ok, [product]} = ResponseParser.parse(card(disabled: "disabled"))
    refute product.in_stock
    html = String.replace(card(), ~r/<button.*?<\/button>/s, "")
    assert {:ok, [product]} = ResponseParser.parse(html)
    refute product.in_stock
  end

  test "duplicate product cards are deduplicated" do
    assert {:ok, [_]} = ResponseParser.parse(card() <> card())
  end

  test "image carousel groups inside a product card are not treated as extra products" do
    carousel = "<div class='group'><div><a href='/mafken/en/milk/p/247170'><img alt='Product image'></a></div></div>"
    html = String.replace(card(), "<div class=\"relative flex flex-col group\">", "<div class=\"relative flex flex-col group\">" <> carousel)
    assert {:ok, [_]} = ResponseParser.parse(html)
  end

  test "explicit no-results pages are empty, unexpected pages are errors" do
    assert {:ok, []} =
             ResponseParser.parse(
               "<main><img src='/images/no-result-found.svg'><div class='text-center'>No results found for<strong>milk</strong></div></main>"
             )

    assert {:error, :unexpected_search_response} =
             ResponseParser.parse("<html>Access denied</html>")

    assert {:error, :unexpected_search_response} =
             ResponseParser.parse("<html>Search Results for milk</html>")
  end

  test "invalid prices fail explicitly instead of producing misleading products" do
    for price <- ["", "Free", "0.00", "-58.00"] do
      assert {:error, {:invalid_product_card, _}} = ResponseParser.parse(card(price: price))
    end
  end

  test "a missing product title is an error even alongside valid cards" do
    broken = String.replace(card(), "line-clamp-2", "missing-title")
    assert {:error, {:invalid_product_card, _}} = ResponseParser.parse(card() <> broken)
  end

  test "HTTP errors and transport failures retain distinct error reasons" do
    for status <- [403, 429, 500] do
      plug = fn conn -> Plug.Conn.send_resp(conn, status, "unavailable") end

      assert {:error, {:carrefour_http_error, ^status}} =
               Client.search("milk", request_options: [plug: plug])
    end

    assert {:error, {:carrefour_request_failed, %Req.TransportError{reason: :timeout}}} =
             Client.search("milk", request_options: [adapter: TimeoutAdapter])
  end

  test "rejects blank queries without issuing a request" do
    assert {:error, :empty_query} = Client.search("  ")
    assert {:error, :invalid_query} = Client.search(nil)
  end
end
