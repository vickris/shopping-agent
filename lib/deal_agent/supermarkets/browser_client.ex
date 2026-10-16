defmodule DealAgent.Supermarkets.BrowserClient do
  @moduledoc """
  Fetches public supermarket search HTML using the isolated Playwright runtime in
  priv/carrefour_browser. Reuses ResponseParser, so both transports have identical
  price and size semantics. At most one local browser lookup runs per store at a time.
  """

  @errors %{
    "browser_http2_error" => :browser_http2_error,
    "browser_dependency_missing" => :browser_dependency_missing,
    "browser_not_installed" => :browser_not_installed,
    "browser_timeout" => :browser_timeout,
    "browser_http_error" => :browser_http_error,
    "browser_search_failed" => :browser_search_failed
  }

  def search(query, store, opts \\ []) do
    DealAgent.Supermarkets.SearchQueue.run(store, fn -> fetch(query, store, opts) end)
  end

  defp fetch(query, store, opts) do
    case Keyword.get(opts, :delivery_session) do
      {owner, session_id} ->
        with {:ok, html} <-
               DealAgent.Delivery.Sessions.search(owner, session_id, Atom.to_string(store), query) do
          decode(Jason.encode!(%{html: html}), 0, store)
        end

      nil ->
        if Application.get_env(:deal_agent, :require_delivery_location, true),
          do: {:error, :location_unconfirmed},
          else: fetch_default(query, store, opts)
    end
  end

  defp fetch_default(query, store, opts) do
    node = Keyword.get(opts, :node_executable, System.find_executable("node"))
    runner = Keyword.get(opts, :runner, &System.cmd/3)
    script = Application.app_dir(:deal_agent, "priv/carrefour_browser/search.mjs")

    if node do
      {output, status} =
        runner.(
          node,
          if(store == :carrefour,
            do: [script, query],
            else: [script, query, Atom.to_string(store)]
          ),
          env: [{"OPENAI_API_KEY", nil}, {"ANTHROPIC_API_KEY", nil}],
          stderr_to_stdout: true
        )

      decode(output, status, store)
    else
      {:error, :browser_dependency_missing}
    end
  rescue
    _error in [ErlangError, ArgumentError] -> {:error, :browser_search_failed}
  end

  defp decode(output, status, store) do
    case Jason.decode(output) do
      {:ok, %{"html" => html}} when status == 0 and is_binary(html) ->
        parser =
          case store do
            :carrefour -> DealAgent.Supermarkets.Carrefour.ResponseParser
            :quickmart -> DealAgent.Supermarkets.Quickmart.ResponseParser
            :naivas -> DealAgent.Supermarkets.Naivas.ResponseParser
          end

        parser.parse(html)

      {:ok, %{"error" => "browser_http_error", "status" => code}} ->
        {:error, {:browser_http_error, code}}

      {:ok, %{"error" => error}} ->
        {:error, Map.get(@errors, error, :browser_search_failed)}

      _ ->
        {:error, :browser_search_failed}
    end
  end
end
