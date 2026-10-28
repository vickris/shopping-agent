defmodule DealAgent.Supermarkets.Registry do
  @moduledoc """
  Registry of supermarkets available to the Deal Agent.
  """

  @supermarkets %{
    carrefour: DealAgent.Supermarkets.Carrefour,
    quickmart: DealAgent.Supermarkets.Quickmart,
    naivas: DealAgent.Supermarkets.Naivas,
    foodplus: DealAgent.Supermarkets.Foodplus
  }

  def fetch(name) do
    Map.fetch(@supermarkets, name)
  end

  def all do
    Map.values(@supermarkets)
  end
end
