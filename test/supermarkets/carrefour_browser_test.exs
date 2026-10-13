defmodule DealAgent.Supermarkets.CarrefourBrowserTest do
  use ExUnit.Case, async: false

  alias DealAgent.Supermarkets.Carrefour.BrowserClient
  alias DealAgent.Supermarkets.Carrefour.Client

  defmodule FakeBrowser do
    def search(query), do: {:ok, [%{id: "browser-product", query: query}]}
  end

  defmodule TransportFailureAdapter do
    def run(request), do: {request, %Req.TransportError{reason: :timeout}}
  end

  test "unreadable HTTP pages fall back to browser retrieval" do
    plug = fn conn -> Plug.Conn.send_resp(conn, 200, "<html><body><p></p></body></html>") end

    assert {:ok, [%{id: "browser-product", query: "milk"}]} =
             Client.search("milk",
               browser_fallback: true,
               browser_client: FakeBrowser,
               request_options: [plug: plug]
             )
  end

  test "rate limits are not retried through a browser" do
    plug = fn conn -> Plug.Conn.send_resp(conn, 429, "limited") end

    assert {:error, {:carrefour_http_error, 429}} =
             Client.search("milk",
               browser_fallback: true,
               browser_client: FakeBrowser,
               request_options: [plug: plug]
             )
  end

  test "transport failures can use the browser fallback" do
    assert {:ok, [%{query: "milk"}]} =
             Client.search("milk",
               browser_fallback: true,
               browser_client: FakeBrowser,
               request_options: [
                 adapter: TransportFailureAdapter
               ]
             )
  end

  test "browser HTML uses the same parser and product size semantics" do
    html = """
    <div class="group">
      <a href="/mafken/en/milk/p/247170"><span class="line-clamp-2">Milk 500ml</span></a>
      <div class="items-baseline"><span>KES</span><span>58.00</span></div>
      <span class="line-clamp-1">500ml</span><button aria-label="Add to cart"></button>
    </div>
    """

    runner = fn executable, [script, query], opts ->
      assert executable == "node-test"
      assert String.ends_with?(script, "/priv/carrefour_browser/search.mjs")
      assert query == "milk & cream"
      assert opts[:env] == [{"OPENAI_API_KEY", nil}, {"ANTHROPIC_API_KEY", nil}]
      {Jason.encode!(%{html: html}), 0}
    end

    assert {:ok, [product]} =
             BrowserClient.search("milk & cream", runner: runner, node_executable: "node-test")

    assert Decimal.equal?(product.price, Decimal.new("58.00"))
    assert Decimal.equal?(product.quantity, Decimal.new("500"))
    assert product.unit == :millilitre
  end

  test "missing browsers, timeouts and malformed output are errors, not empty searches" do
    for error <- [
          :browser_not_installed,
          :browser_dependency_missing,
          :browser_timeout,
          :browser_http2_error
        ] do
      runner = fn _, _, _ -> {Jason.encode!(%{error: Atom.to_string(error)}), 1} end

      assert {:error, ^error} =
               BrowserClient.search("milk", node_executable: "node-test", runner: runner)
    end

    runner = fn _, _, _ -> {"invalid runtime output", 1} end

    assert {:error, :browser_search_failed} =
             BrowserClient.search("milk", node_executable: "node-test", runner: runner)
  end

  test "Quickmart default search scrapes rendered HTML through its own parser" do
    html = """
    <div id="products-listing"><div class="productInfoJs">
      <a class="products-title" href="/milk">Milk 500Ml</a>
      <span class="products-price-new">KES 65.00</span>
      <input name="selprod_id" value="802"><div class="quantity" data-stock="20"></div>
      <button name="btnAddToCart">Add</button>
    </div></div>
    """

    runner = fn _, [_, "milk", "quickmart"], opts ->
      assert opts[:env] == [{"OPENAI_API_KEY", nil}, {"ANTHROPIC_API_KEY", nil}]
      {Jason.encode!(%{html: html}), 0}
    end

    assert {:ok, result} =
             DealAgent.Supermarkets.Quickmart.search(
               DealAgent.Shopping.Item.new("milk"),
               node_executable: "node-test",
               runner: runner
             )

    assert [%{supermarket: :quickmart, in_stock: true} = product] = result.products
    assert Decimal.equal?(product.price, "65.00")
    assert Decimal.equal?(product.quantity, "500")
  end

  test "search page links encode only the product name" do
    assert Client.search_url("milk & cream") ==
             "https://www.carrefour.ke/mafken/en/search?keyword=milk+%26+cream"
  end
end
