defmodule DealAgent.Supermarkets.Quickmart.BrowserClient do
  @moduledoc "Scrapes Quickmart Ruaka through the shared isolated headless browser runtime."
  def search(query, opts \\ []),
    do: DealAgent.Supermarkets.BrowserClient.search(query, :quickmart, opts)
end
