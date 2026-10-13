defmodule DealAgent.Shopping.Product do
  @moduledoc """
  Normalized product representation returned by supermarket adapters.

  Price is the selling price of one listed pack. Quantity is total pack
  contents in `unit`; both quantity and unit are nil when the size is unknown.
  """

  @enforce_keys [
    :id,
    :name,
    :price,
    :currency,
    :quantity,
    :unit,
    :supermarket
  ]

  defstruct [
    :id,
    :name,
    :brand,
    :price,
    :currency,
    :quantity,
    :unit,
    :supermarket,
    :url,
    :image_url,
    :in_stock,
    :raw
  ]

  @type unit ::
          :each
          | :gram
          | :kilogram
          | :millilitre
          | :litre

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          brand: String.t() | nil,
          price: Decimal.t(),
          currency: atom(),
          quantity: Decimal.t() | nil,
          unit: unit() | nil,
          supermarket: atom(),
          url: String.t() | nil,
          image_url: String.t() | nil,
          in_stock: boolean(),
          raw: term()
        }
end
