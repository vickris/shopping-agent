defmodule DealAgent.Tools.Registry do
  @moduledoc """
  Registry for tools that can be used by the agent.
  """

  @tools %{
    capture_intent: DealAgent.Tools.CaptureIntent
  }

  @doc """
  The `%{name => module}` map passed to `BeamAgent.API.run/2`'s `:tools`
  option. BeamAgent's own `BeamAgent.Tools.Registry` holds no tools — it
  dispatches against whatever map flows down from the run, and its
  `call/3` guards on `is_map/1`, so this must stay a map, not a list.
  """
  def tools, do: @tools

  def call(name, args) do
    case Map.fetch(@tools, name) do
      {:ok, module} ->
        module.execute(args)

      :error ->
        {:error, :unknown_tool}
    end
  end
end
