defmodule DealAgent.Supermarkets.Quickmart.Client do
  @moduledoc "Fetches the initial public Quickmart Ruaka search page without a shopper location."
  alias DealAgent.Supermarkets.Quickmart.ResponseParser

  def search_url(query),
    do:
      "https://www.quickmart.co.ke/shops/products/1/keyword-" <>
        URI.encode(String.trim(query), &URI.char_unreserved?/1)

  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) do
    if String.trim(query) == "" do
      {:error, :empty_query}
    else
      options =
        Keyword.merge(
          [
            url: search_url(query),
            retry: false,
            receive_timeout: 15_000,
            connect_options: [timeout: 5_000],
            headers: [
              {"accept", "text/html"},
              {"user-agent", "DealAgent/0.1 (Quickmart product search)"}
            ]
          ],
          Keyword.get(opts, :request_options, [])
        )

      case Req.get(options) do
        {:ok, %{status: 200, body: body}} -> ResponseParser.parse(body)
        {:ok, %{status: status}} -> {:error, {:quickmart_http_error, status}}
        {:error, reason} -> {:error, {:quickmart_request_failed, reason}}
      end
    end
  end

  def search(_, _), do: {:error, :invalid_query}
end
