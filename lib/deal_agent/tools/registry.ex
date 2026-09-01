defmodule DealAgent.Tools.Registry do
  @moduledoc """
  Registry for tools that can be used by the agent.
  """

  @tools %{
    capture_intent: DealAgent.Tools.CaptureIntent
  }

  def call(name, args) do
    case Map.fetch(@tools, name) do
      {:ok, module} ->
        module.execute(args)

      :error ->
        {:error, :unknown_tool}
    end
  end
end
