defmodule DealAgent.Supermarkets.Foodplus.BrowserClient do
  def search(query, opts \\ []),
    do: DealAgent.Supermarkets.BrowserClient.search(query, :foodplus, opts)
end
