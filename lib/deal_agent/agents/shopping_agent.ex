defmodule DealAgent.Agents.ShoppingAgent do
  @moduledoc """
  Interprets natural-language shopping commands using BeamAgent.
  """

  alias DealAgent.Shopping.IntentConverter

  @spec interpret(String.t(), keyword()) ::
          {:ok, DealAgent.Shopping.Intent.t()}
          | {:error, term()}
  def interpret(input, opts \\ []) do
    llm =
      opts
      |> Keyword.get_lazy(:llm, &default_llm/0)
      |> normalize_llm()

    run =
      case run_agent(input, llm) do
        {:ok, run} -> run
        {:error, run} -> run
      end

    with {:ok, payload} <- extract_intent(run),
         {:ok, intent} <- IntentConverter.convert(payload, input) do
      {:ok, intent}
    end
  end

  defp run_agent(input, llm) do
    BeamAgent.API.run(
      input,
      llm: llm,
      tools: DealAgent.Tools.Registry.tools(),
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

  # `:llm` may be given as `{module, opts}` or a bare `module`.
  defp normalize_llm({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp normalize_llm(module) when is_atom(module), do: {module, []}

  defp default_llm do
    {
      DealAgent.LLM.OpenAI,
      [
        api_key:
          Application.fetch_env!(
            :deal_agent,
            :openai_api_key
          ),
        model: "gpt-5.6-luna",
        tools: [
          DealAgent.Tools.CaptureIntent
        ]
      ]
    }
  end

  defp extract_intent(run) do
    run.trace
    |> Enum.reverse()
    |> Enum.find(fn step ->
      step.type == :tool_completed &&
        step.payload.tool == :capture_intent
    end)
    |> case do
      nil -> {:error, :intent_not_captured}
      step -> {:ok, step.payload.result}
    end
  end
end
