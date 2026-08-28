defmodule DealAgent.Shopping.ShoppingList do
  @moduledoc """
  Users current shopping List
  """
  alias DealAgent.Shopping.Item

  defstruct items: []

  @type t :: %__MODULE__{
          items: [Item.t()]
        }

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec add_item(t(), Item.t()) :: t()
  def add_item(%__MODULE__{} = list, %Item{} = item) do
    %{list | items: list.items ++ [item]}
  end

  @spec remove_item(t(), String.t()) :: t()
  def remove_item(%__MODULE__{} = list, item_id) do
    items =
      Enum.reject(
        list.items,
        &(&1.id == item_id)
      )

    %{list | items: items}
  end

  @spec update_item(t(), String.t(), map()) :: t()
  def update_item(%__MODULE__{} = list, item_id, attrs) do
    items =
      Enum.map(list.items, fn
        %Item{id: ^item_id} = item ->
          update_item_fields(item, attrs)

        item ->
          item
      end)

    %{list | items: items}
  end

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{items: items}) do
    items == []
  end

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{items: items}) do
    length(items)
  end

  defp update_item_fields(item, attrs) do
    %{
      item
      | name: Map.get(attrs, :name, item.name),
        quantity: Map.get(attrs, :quantity, item.quantity),
        unit: Map.get(attrs, :unit, item.unit),
        notes: Map.get(attrs, :notes, item.notes)
    }
  end
end
