defmodule DealAgent.Supermarkets.Naivas.Client do
  @moduledoc "Fetches the initial public Naivas Nairobi search page without a shopper location."
  alias DealAgent.Supermarkets.Naivas.ResponseParser

  def search_url(query),
    do: "https://www.naivas.online/search?" <> URI.encode_query(%{"term" => String.trim(query)})

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
              {"user-agent", "DealAgent/0.1 (Naivas product search)"}
            ]
          ],
          Keyword.get(opts, :request_options, [])
        )

      case Req.get(options) do
        {:ok, %{status: 200, body: body}} -> ResponseParser.parse(body)
        {:ok, %{status: status}} -> {:error, {:naivas_http_error, status}}
        {:error, reason} -> {:error, {:naivas_request_failed, reason}}
      end
    end
  end

  def search(_, _), do: {:error, :invalid_query}
end
