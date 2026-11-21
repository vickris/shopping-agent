defmodule DealAgent.Supermarkets.Naivas.ResponseParser do
  @moduledoc "Parses Naivas search cards, preserving selling prices and explicit title sizes."
  alias DealAgent.Supermarkets.Carrefour.Size

  defp parse_legacy(html) when is_binary(html) do
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

  def parse(html) when is_binary(html) do
    with {:ok, doc} <- Floki.parse_document(html) do
      main_text = doc |> Floki.find("main") |> Floki.text(sep: " ")

      case Regex.run(~r/\b([\d,]+)\s+Result\(s\)/, main_text) do
        [_, "0"] -> {:ok, []}
        [_, _count] -> parse_modern(doc)
        _ -> parse_legacy(html)
      end
    end
  end

  def parse(_), do: {:error, :unexpected_search_response}

  defp parse_modern(doc) do
    cards =
      Floki.find(doc, "main div.group") |> Enum.filter(&(Floki.find(&1, "p.line-clamp-2") != []))

    if cards == [] do
      {:error, :unexpected_search_response}
    else
      Enum.reduce_while(cards, {:ok, []}, fn card, {:ok, products} ->
        href = Floki.attribute(card, "a[href]", "href") |> List.first()
        image = Floki.attribute(card, "img", "src") |> List.first()
        name = card |> Floki.find("p.line-clamp-2") |> Floki.text() |> String.trim()
        price_text = card |> Floki.find("span.font-bold") |> Floki.text(sep: " ") |> String.trim()

        url =
          if is_binary(href), do: URI.merge("https://www.naivas.online", href) |> URI.to_string()

        with true <-
               is_binary(url) and URI.parse(url).host in ["www.naivas.online", "naivas.online"],
             true <- name != "",
             [_, id] <- Regex.run(~r{/product/(\d+)/}, image || ""),
             [_, value] <- Regex.run(~r/^KES\s+([\d,]+(?:\.\d{1,2})?)$/, price_text),
             {price, ""} <- Decimal.parse(String.replace(value, ",", "")),
             true <- Decimal.compare(price, 0) == :gt do
          {quantity, unit, label} = title_size(name)

          buttons =
            Floki.find(
              card,
              "button[aria-label='Add to cart'], button[aria-label='Expand quantity stepper']"
            )

          product = %{
            id: id,
            name: name,
            brand: nil,
            price: price,
            quantity: quantity,
            unit: unit,
            url: url,
            image_url: image,
            in_stock: Enum.any?(buttons, &(Floki.attribute(&1, "disabled") == [])),
            source: %{
              layout: :react,
              id_source: :product_image_path,
              size_label: label,
              size_source: :title
            }
          }

          {:cont, {:ok, [product | products]}}
        else
          _ -> {:halt, {:error, {:invalid_product_card, href}}}
        end
      end)
      |> case do
        {:ok, products} -> {:ok, products |> Enum.reverse() |> Enum.uniq_by(& &1.id)}
        error -> error
      end
    end
  end

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
