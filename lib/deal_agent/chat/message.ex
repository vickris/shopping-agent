defmodule DealAgent.Chat.Message do
  @moduledoc """
  Represents a message in a shopper conversation.
  """

  @enforce_keys [:id, :role, :content]

  defstruct [:id, :role, :content, :inserted_at]

  @type role :: :user | :assistant | :system
  @type t :: %__MODULE__{
          id: String.t(),
          role: role(),
          content: String.t(),
          inserted_at: DateTime.t() | nil
        }

  def new(role, content) when role in [:user, :assistant, :system] do
    %__MODULE__{
      id: generate_id(),
      role: role,
      content: content,
      inserted_at: DateTime.utc_now()
    }
  end

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end
