defmodule DealAgent.Supermarkets.Naivas.BrowserClient do
  @moduledoc "Scrapes Naivas Nairobi through the shared isolated headless browser runtime."
  def search(query, opts \\ []),
    do: DealAgent.Supermarkets.BrowserClient.search(query, :naivas, opts)
end
