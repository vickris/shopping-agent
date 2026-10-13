defmodule DealAgent.Supermarkets.Quickmart.ResponseParser do
  @moduledoc "Parses Quickmart's branch listing cards, retaining labelled title size and selling price."
  alias DealAgent.Supermarkets.Carrefour.Size

  def parse(html) when is_binary(html) do
    with {:ok, doc} <- Floki.parse_document(html) do
      # Scope to the actual search listing: never accept home-page recommendations.
      cards = Floki.find(doc, "#products-listing .productInfoJs")

      case cards do
        [] ->
          empty_result(doc)

        _ ->
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
      end
    end
  end

  def parse(_), do: {:error, :unexpected_search_response}

  defp empty_result(doc) do
    counts =
      Floki.attribute(doc, "#frmProductSearchPaging input[name='recordDisplayCount']", "value")

    if counts == ["0"] and Floki.find(doc, "#products-listing") != [],
      do: {:ok, []},
      else: {:error, :unexpected_search_response}
  end

  defp parse_card(card) do
    name = card |> Floki.find("a.products-title") |> Floki.text() |> String.trim()
    href = Floki.attribute(card, "a.products-title", "href") |> List.first()
    id = Floki.attribute(card, "input[name='selprod_id']", "value") |> List.first()
    price_text = card |> Floki.find(".products-price-new") |> Floki.text() |> String.trim()
    stock = Floki.attribute(card, ".quantity[data-stock]", "data-stock") |> List.first()

    with true <- name != "" and is_binary(id) and id != "",
         true <-
           is_binary(href) and String.starts_with?(href, "/") and
             not String.starts_with?(href, "//"),
         [_, price_value] <- Regex.run(~r/^KES\s+([\d,]+(?:\.\d{1,2})?)$/, price_text),
         {price, ""} <- Decimal.parse(String.replace(price_value, ",", "")),
         true <- Decimal.compare(price, 0) == :gt do
      {quantity, unit, size_label} = title_size(name)

      available =
        case Integer.parse(stock || "") do
          {value, ""} -> value > 0
          _ -> false
        end

      {:ok,
       %{
         id: id,
         name: name,
         brand: nil,
         price: price,
         quantity: quantity,
         unit: unit,
         url: URI.merge("https://www.quickmart.co.ke", href) |> URI.to_string(),
         image_url: Floki.attribute(card, ".products-img img", "src") |> List.first(),
         in_stock:
           available and Floki.find(card, "button[name='btnAddToCart']:not([disabled])") != [],
         source: %{
           html: Floki.raw_html(card),
           size_label: size_label,
           size_source: :title,
           branch: "Ruaka"
         }
       }}
    else
      _ -> {:error, {:invalid_product_card, href}}
    end
  end

  defp title_size(name) do
    # A single explicitly printed amount, including Gms spelling. Bundles remain unknown.
    matches = Regex.scan(~r/\b\d+(?:\.\d+)?\s*(?:ml|kg|gms?|g|l|pieces?|pcs?)\b/i, name)

    case matches do
      [[label]] ->
        if Regex.match?(~r/\+|\b\d+\s*x\s*|\bx\s*\d+|\b(?:pack|pieces)\s*of\s*\d+/i, name) do
          {nil, nil, nil}
        else
          normalized = Regex.replace(~r/gms\b/i, label, "gm")
          {quantity, unit} = Size.parse(normalized)
          {quantity, unit, label}
        end

      _ ->
        {nil, nil, nil}
    end
  end
end
