defmodule DealAgent.Supermarkets.Carrefour.BrowserClient do
  @moduledoc "Scrapes Carrefour through the shared isolated headless browser runtime."
  def search(query, opts \\ []),
    do: DealAgent.Supermarkets.BrowserClient.search(query, :carrefour, opts)
end
