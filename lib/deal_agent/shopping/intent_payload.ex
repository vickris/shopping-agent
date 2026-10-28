defmodule DealAgent.Shopping.IntentPayload do
  @moduledoc """
  Represents untrusted structured intent data produced by an agent.

  Payloads must be validated before becoming Shopping.Intent values.
  """

  @actions ~w(
    add_items
    add_item
    remove_item
    clear_list
    compare
    list_supermarkets
  )

  @units ~w(
    each
    gram
    kilogram
    millilitre
    litre
  )

  @type t :: %{
          required(:action) => String.t(),
          optional(:name) => String.t(),
          optional(:quantity) => String.t(),
          optional(:unit) => String.t(),
          optional(:items) => [map()] | nil,
          optional(:supermarkets) => [String.t()] | nil
        }

  def actions, do: @actions
  def units, do: @units
end
