defmodule DealAgent.Supermarkets.Carrefour.Client do
  @moduledoc """
  HTTP boundary for Carrefour product search.
  """

  def search(_query) do
    {:error, :not_implemented}
  end
end
