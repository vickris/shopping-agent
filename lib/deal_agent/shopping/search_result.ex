defmodule DealAgent.Shopping.SearchResult do
  @moduledoc """
  Represents the result of searching one supermarket for one requested item.
  """

  alias DealAgent.Shopping.Item
  alias DealAgent.Shopping.Product

  @enforce_keys [
    :supermarket,
    :query,
    :products
  ]

  defstruct [
    :supermarket,
    :query,
    :requested_item,
    :products,
    :metadata
  ]

  @type t :: %__MODULE__{
          supermarket: atom(),
          query: String.t(),
          requested_item: Item.t() | nil,
          products: [Product.t()],
          metadata: map() | nil
        }
end
