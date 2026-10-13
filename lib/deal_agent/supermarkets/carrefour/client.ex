defmodule DealAgent.Supermarkets.Carrefour.Client do
  @moduledoc """
  Fetches Carrefour Kenya's public search HTML and parses its product cards.

  Only the initial search page is fetched. Prices and availability reflect the
  site's default delivery area, not a shopper-selected branch. Request options
  can be injected through `search/2` for offline tests.
  """

  alias DealAgent.Supermarkets.Carrefour.ResponseParser

  @url "https://www.carrefour.ke/mafken/en/search"

  @doc "The public Carrefour search page for the item's product name."
  def search_url(query) when is_binary(query) do
    @url <> "?" <> URI.encode_query(%{"keyword" => String.trim(query)})
  end

  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) do
    case String.trim(query) do
      "" ->
        {:error, :empty_query}

      query ->
        result = fetch(query, opts)
        maybe_use_browser(result, query, opts)
    end
  end

  def search(_query, _opts), do: {:error, :invalid_query}

  defp maybe_use_browser(result, query, opts) do
    enabled? =
      Keyword.get(
        opts,
        :browser_fallback,
        Application.get_env(:deal_agent, :carrefour_browser_fallback, true)
      )

    if enabled? and browser_retryable?(result) do
      browser = Keyword.get(opts, :browser_client, DealAgent.Supermarkets.Carrefour.BrowserClient)
      browser.search(query)
    else
      result
    end
  end

  defp browser_retryable?({:error, :unexpected_search_response}), do: true
  defp browser_retryable?({:error, {:carrefour_request_failed, _reason}}), do: true
  defp browser_retryable?({:error, {:carrefour_http_error, 403}}), do: true
  defp browser_retryable?(_result), do: false

  defp fetch(query, opts) do
    request_options =
      Keyword.merge(
        [
          url: @url,
          params: [keyword: query],
          headers: [
            {"accept", "text/html"},
            {"user-agent", "DealAgent/0.1 (Carrefour product search)"}
          ],
          receive_timeout: 15_000,
          connect_options: [timeout: 5_000],
          retry: false
        ],
        Keyword.get(opts, :request_options, [])
      )

    case Req.get(request_options) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        ResponseParser.parse(body)

      {:ok, %{status: 200}} ->
        {:error, :unexpected_search_response}

      {:ok, %{status: status}} ->
        {:error, {:carrefour_http_error, status}}

      {:error, reason} ->
        {:error, {:carrefour_request_failed, reason}}
    end
  end
end
