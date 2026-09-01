defmodule DealAgent.Agents.IntentVerifier do
  @behaviour BeamAgent.Verifier.Behaviour

  @impl true
  def verify(run, _opts) do
    with {:ok, payload} <- extract_payload(run),
         {:ok, _intent} <-
           DealAgent.Shopping.IntentConverter.convert(
             payload,
             run.goal
           ) do
      :ok
    end
  end

  defp extract_payload(run) do
    run.trace
    |> Enum.reverse()
    |> Enum.find(fn step ->
      step.type == :tool_completed &&
        step.payload.tool == :capture_intent
    end)
    |> case do
      nil ->
        {:error, :intent_not_captured}

      step ->
        {:ok, step.payload.result}
    end
  end
end
