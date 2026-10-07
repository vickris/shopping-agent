defmodule DealAgent.Supermarkets.Behaviour do
  @moduledoc """
  Behaviour implemented by supermarket adapters.
  """

  alias DealAgent.Shopping.Item
  alias DealAgent.Shopping.SearchResult

  @callback name() :: atom()

  @callback search(Item.t(), keyword()) ::
              {:ok, SearchResult.t()}
              | {:error, term()}
end
