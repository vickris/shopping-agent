defmodule DealAgent.Shopping.IntentPayload do
  @moduledoc """
  Represents untrusted structured intent data produced by an agent.

  Payloads must be validated before becoming Shopping.Intent values.
  """

  @actions ~w(
    add_item
    remove_item
    clear_list
    compare
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
          optional(:unit) => String.t()
        }

  def actions, do: @actions
  def units, do: @units
end
