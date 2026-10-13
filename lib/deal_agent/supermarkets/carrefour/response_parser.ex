defmodule DealAgent.Supermarkets.Carrefour.ResponseParser do
  @moduledoc """
  Parses the public Carrefour Kenya search card markup observed in October 2026.

  Unexpected pages and malformed cards are errors, not empty search results.
  Optional brand data is not inferred from the title. Original card HTML and size
  labels are retained for diagnostics and future matching.
  """

  alias DealAgent.Supermarkets.Carrefour.Size

  @origin "https://www.carrefour.ke"

  def parse(html) when is_binary(html) do
    with {:ok, document} <- Floki.parse_document(html) do
      cards = Floki.find(document, "div.group") |> Enum.filter(&product_card?/1)

      case cards do
        [] -> empty_result(document)
        cards -> parse_cards(cards)
      end
    end
  end

  def parse(_body), do: {:error, :unexpected_search_response}

  defp product_card?(card) do
    # Carousel wrappers also use .group and contain product image links.
    # Only the outer card has its product-title link as a direct child.
    card
    |> Floki.children(include_text: false)
    |> Enum.any?(fn
      {"a", attributes, _children} ->
        attributes |> List.keyfind("href", 0, {"href", ""}) |> elem(1) |> String.contains?("/p/")

      _ -> false
    end)
  end

  defp empty_result(document) do
    empty_marker = Floki.find(document, "img[src*='no-result-found.svg']")

    empty_message? =
      document
      |> Floki.find("div.text-center")
      |> Enum.any?(fn element ->
        element |> Floki.text() |> String.trim() |> String.starts_with?("No results found for")
      end)

    if empty_marker != [] and empty_message? do
      {:ok, []}
    else
      {:error, :unexpected_search_response}
    end
  end

  defp parse_cards(cards) do
    Enum.reduce_while(cards, {:ok, []}, fn card, {:ok, products} ->
      case parse_card(card) do
        {:ok, product} -> {:cont, {:ok, [product | products]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, products} -> {:ok, products |> Enum.reverse() |> Enum.uniq_by(& &1.id)}
      error -> error
    end
  end

  defp parse_card(card) do
    name = card |> Floki.find("a[href*='/p/'] span.line-clamp-2") |> Floki.text() |> String.trim()
    href = Floki.attribute(card, "a[href*='/p/']", "href") |> List.first()

    price_text =
      card
      |> Floki.find("div.items-baseline")
      |> Floki.filter_out(".line-through, del, s")
      |> Floki.text(sep: " ")
      |> String.trim()

    size_label = card |> Floki.find("span.line-clamp-1") |> Floki.text() |> String.trim()

    with [_, id] <- Regex.run(~r{/p/([^/?#]+)}, href || ""),
         true <- name != "",
         {:ok, price} <- parse_price(price_text) do
      {quantity, unit} = Size.parse(size_label)
      button = Floki.find(card, "button[aria-label='Add to cart']")

      {:ok,
       %{
         id: id,
         name: name,
         brand: nil,
         price: price,
         quantity: quantity,
         unit: unit,
         url: URI.merge(@origin, href) |> URI.to_string(),
         image_url: Floki.attribute(card, "img[alt^='Product image']", "src") |> List.first(),
         in_stock: button != [] and Floki.attribute(button, "disabled") == [],
         source: %{
           html: Floki.raw_html(card),
           size_label: size_label,
           size_status: if(quantity, do: :known, else: :unknown)
         }
       }}
    else
      _ -> {:error, {:invalid_product_card, href}}
    end
  end

  defp parse_price(text) do
    # Read the current price after KES, leaving any struck-through former price
    # or promotion text out of the amount.
    case Regex.run(~r/^KES\s+(\d+(?:,\d{3})*(?:\.\d{1,2})?)(?:\s|$)/, text) do
      [_, value] ->
        price = value |> String.replace(",", "") |> Decimal.new()
        if Decimal.compare(price, 0) == :gt, do: {:ok, price}, else: {:error, :invalid_price}

      _ ->
        {:error, :invalid_price}
    end
  end
end
