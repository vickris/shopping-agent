defmodule DealAgent.Supermarkets.Foodplus.ResponseParser do
  @moduledoc "Parses Foodplus Magento cards using final selling prices and explicit pack sizes."
  alias DealAgent.Supermarkets.Carrefour.Size

  def parse(html) when is_binary(html) do
    with {:ok, doc} <- Floki.parse_document(html),
         true <-
           doc
           |> Floki.find("h1.page-title")
           |> Floki.text()
           |> String.contains?("Search results for:") do
      cards = Floki.find(doc, ".products-grid li.product-item")

      cond do
        cards != [] ->
          Enum.reduce_while(cards, {:ok, []}, fn card, {:ok, products} ->
            case parse_card(card) do
              {:ok, product} -> {:cont, {:ok, [product | products]}}
              error -> {:halt, error}
            end
          end)
          |> case do
            {:ok, products} -> {:ok, products |> Enum.reverse() |> Enum.uniq_by(& &1.id)}
            error -> error
          end

        doc
        |> Floki.find(".message.notice")
        |> Floki.text()
        |> String.contains?("Your search returned no results") ->
          {:ok, []}

        true ->
          {:error, :unexpected_search_response}
      end
    else
      _ -> {:error, :unexpected_search_response}
    end
  end

  def parse(_), do: {:error, :unexpected_search_response}

  defp parse_card(card) do
    link = Floki.find(card, "a.product-item-link")
    name = link |> Floki.text() |> String.trim()
    href = Floki.attribute(link, "href") |> List.first()
    id = Floki.attribute(card, ".price-box[data-product-id]", "data-product-id") |> List.first()

    value =
      Floki.attribute(card, "[data-price-type='finalPrice']", "data-price-amount") |> List.first()

    with true <- name != "" and is_binary(id) and Regex.match?(~r/^\d+$/, id),
         %URI{scheme: "https", host: host, path: path, userinfo: nil, port: 443} <-
           URI.parse(href || ""),
         true <-
           host in ["foodplus.co.ke", "www.foodplus.co.ke"] and
             String.ends_with?(path || "", ".html"),
         true <- is_binary(value) and Regex.match?(~r/^\d+(?:\.\d{1,2})?$/, value),
         {price, ""} <- Decimal.parse(value),
         true <- Decimal.compare(price, 0) == :gt do
      {quantity, unit, label} = title_size(name)

      {:ok,
       %{
         id: id,
         name: name,
         brand: nil,
         price: price,
         quantity: quantity,
         unit: unit,
         url: href,
         image_url: Floki.attribute(card, "img.product-image-photo", "src") |> List.first(),
         in_stock:
           Floki.find(
             card,
             "form[data-role='tocart-form'][data-product-id='#{id}'] button.tocart:not([disabled])"
           ) != [],
         source: %{size_label: label, size_source: :title}
       }}
    else
      _ -> {:error, {:invalid_product_card, id}}
    end
  end

  defp title_size(name) do
    # Reject ambiguous ranges, bundles and multiple amounts rather than guessing.
    matches =
      Regex.scan(~r/\b\d+(?:\.\d+)?\s*(?:ml|ltr|litres?|kg|gms?|g|l|pieces?|pcs?)\b/i, name)

    case matches do
      [[label]] ->
        if Regex.match?(~r/\+|\d\s*[-–]\s*\d|\b\d+\s*x\s*|\bx\s*\d+|\bpack\s*of\s*\d+/i, name) do
          {nil, nil, nil}
        else
          normalized =
            label
            |> String.downcase()
            |> String.replace(~r/ltr|litres?/, "l")
            |> String.replace(~r/gms\b/, "gm")

          {quantity, unit} = Size.parse(normalized)
          {quantity, unit, label}
        end

      _ ->
        {nil, nil, nil}
    end
  end
end
