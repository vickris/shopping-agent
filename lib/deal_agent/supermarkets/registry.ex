defmodule DealAgent.Supermarkets.Registry do
  @moduledoc """
  Registry of supermarkets available to the Deal Agent.
  """

  @supermarkets %{
    carrefour: DealAgent.Supermarkets.Carrefour
  }

  def fetch(name) do
    Map.fetch(@supermarkets, name)
  end

  def all do
    Map.values(@supermarkets)
  end
end
