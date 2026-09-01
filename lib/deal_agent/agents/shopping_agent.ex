defmodule DealAgent.Agents.ShoppingAgent do
  @moduledoc """
  Interprets natural-language shopping commands using BeamAgent.
  """

  alias DealAgent.Shopping.IntentConverter

  @spec interpret(String.t()) ::
          {:ok, DealAgent.Shopping.Intent.t()}
          | {:error, term()}
  def interpret(input, opts \\ []) do
    llm =
      Keyword.get_lazy(
        opts,
        :llm,
        &default_llm/0
      )

    with {:ok, run} <- run_agent(input),
         {:ok, payload} <- extract_intent(run),
         {:ok, intent} <-
           IntentConverter.convert(
             payload,
             input
           ) do
      {:ok, intent}
    end
  end

  defp run_agent(input) do
    BeamAgent.API.run(
      input,
      llm: llm(),
      tools: DealAgent.Tools.Registry,
      verification: [
        required_tools: [:capture_intent]
      ],
      guardrails: [
        max_iterations: 3,
        max_tool_calls: 1,
        max_execution_time_ms: 10_000
      ]
    )
  end

  defp extract_intent(run) do
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
