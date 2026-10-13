defmodule DealAgent.Supermarkets.Naivas.ResponseParser do
  @moduledoc "Parses Naivas search cards, preserving selling prices and explicit title sizes."
  alias DealAgent.Supermarkets.Carrefour.Size

  def parse(html) when is_binary(html) do
    with {:ok, doc} <- Floki.parse_document(html),
         heading when is_binary(heading) <-
           doc
           |> Floki.find("h2")
           |> Enum.map(&Floki.text/1)
           |> Enum.find(&Regex.match?(~r/^\s*[\d,]+\s+Search Results Found\s*$/, &1)) do
      cards =
        Floki.find(doc, "div.border-naivas-bg")
        |> Enum.filter(&(Floki.find(&1, "input[name='product_id']") != []))

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

        Regex.match?(~r/^\s*0\s+Search Results Found\s*$/, heading) ->
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
    name = card |> Floki.find("a span.line-clamp-2") |> Floki.text() |> String.trim()
    href = Floki.attribute(card, "a[title]", "href") |> List.first()
    id = Floki.attribute(card, "input[name='product_id']", "value") |> List.first()

    price_text =
      card |> Floki.find(".product-price span.font-bold") |> Floki.text() |> String.trim()

    price_text = String.replace(price_text, "\u00A0", " ")

    with true <- name != "" and is_binary(id) and id != "",
         %URI{scheme: "https", host: host} <- URI.parse(href || ""),
         true <- host in ["www.naivas.online", "naivas.online"],
         [_, value] <- Regex.run(~r/^KES\s+([\d,]+(?:\.\d{1,2})?)$/, price_text),
         {price, ""} <- Decimal.parse(String.replace(value, ",", "")),
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
         image_url: Floki.attribute(card, ".product-card-img img", "src") |> List.first(),
         in_stock:
           Enum.any?(
             Floki.find(card, "form button:not([disabled])"),
             &String.contains?(Floki.text(&1), "ADD TO CART")
           ),
         source: %{size_label: label, size_source: :title, delivery_area: "Nairobi"}
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
