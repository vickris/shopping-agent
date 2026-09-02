defmodule DealAgent.Shopping.Intent do
  @moduledoc """
  Represents the intent of a shopper's message in the shopping context.
  """

  alias DealAgent.Shopping.Item

  @type action ::
          :add_item
          | :remove_item
          | :clear_list
          | :compare
          | :unknown

  @type t :: %__MODULE__{
          action: action(),
          item: Item.t() | nil,
          item_name: String.t() | nil,
          raw_input: String.t() | nil
        }

  defstruct [
    :action,
    :item,
    :item_name,
    :raw_input
  ]

  @spec add_item(Item.t(), String.t()) :: t()
  def add_item(%Item{} = item, raw_input) do
    %__MODULE__{
      action: :add_item,
      item: item,
      raw_input: raw_input,
      item_name: item.name
    }
  end

  @spec remove_item(String.t(), String.t()) :: t()
  def remove_item(item_name, raw_input) do
    %__MODULE__{
      action: :remove_item,
      item_name: String.trim(item_name),
      raw_input: raw_input
    }
  end

  @spec clear_list(String.t()) :: t()
  def clear_list(raw_input) do
    %__MODULE__{
      action: :clear_list,
      raw_input: raw_input
    }
  end

  @spec compare(String.t()) :: t()
  def compare(raw_input) do
    %__MODULE__{
      action: :compare,
      raw_input: raw_input
    }
  end

  @spec unknown(String.t()) :: t()
  def unknown(raw_input) do
    %__MODULE__{
      action: :unknown,
      raw_input: raw_input
    }
  end
end
