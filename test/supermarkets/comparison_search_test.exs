defmodule DealAgent.Supermarkets.ComparisonSearchTest do
  use ExUnit.Case, async: false
  alias DealAgent.Supermarkets.BrowserClient

  test "catalogue comparison is explicit and does not disable checkout location checks" do
    old = Application.get_env(:deal_agent, :require_delivery_location)
    Application.put_env(:deal_agent, :require_delivery_location, true)
    on_exit(fn -> Application.put_env(:deal_agent, :require_delivery_location, old) end)
    owner = self()

    runner = fn _, _, _ ->
      send(owner, :catalogue_requested)

      {Jason.encode!(%{
         html:
           "<h1 class='page-title'>Search results for: milk</h1><div class='message notice'>Your search returned no results.</div>"
       }), 0}
    end

    options = [node_executable: "fixture-node", runner: runner]
    assert {:error, :location_unconfirmed} = BrowserClient.search("milk", :foodplus, options)
    refute_received :catalogue_requested

    assert {:ok, []} =
             BrowserClient.search("milk", :foodplus, Keyword.put(options, :comparison_only, true))

    assert_received :catalogue_requested
    assert Application.get_env(:deal_agent, :require_delivery_location)
  end
end
