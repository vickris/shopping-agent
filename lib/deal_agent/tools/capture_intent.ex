defmodule DealAgent.Tools.CaptureIntent do
  @moduledoc """
  Captures a structured shopping intent proposed by the model.
  """

  @behaviour BeamAgent.Tools.Behaviour

  @impl true
  def name, do: :capture_intent

  @impl true
  def description do
    """
    Records the user's shopping intent.

    Supported actions:
    add_item, remove_item, clear_list, compare.
    """
  end

  def parameters do
    %{
      type: "object",
      properties: %{
        action: %{
          type: "string",
          enum: [
            "add_item",
            "remove_item",
            "clear_list",
            "compare"
          ]
        },
        name: %{
          type: ["string", "null"]
        },
        quantity: %{
          type: ["string", "null"]
        },
        unit: %{
          type: ["string", "null"],
          enum: [
            "each",
            "gram",
            "kilogram",
            "millilitre",
            "litre",
            nil
          ]
        }
      },
      required: [
        "action",
        "name",
        "quantity",
        "unit"
      ],
      additionalProperties: false
    }
  end

  @impl true
  def execute(args) when is_map(args) do
    {:ok, normalize(args)}
  end

  def execute(_args) do
    {:error, :invalid_intent}
  end

  defp normalize(args) do
    %{
      action: get(args, :action),
      name: get(args, :name),
      quantity: get(args, :quantity),
      unit: get(args, :unit)
    }
  end

  defp get(args, key) do
    Map.get(args, key) ||
      Map.get(args, Atom.to_string(key))
  end
end
