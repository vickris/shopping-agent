defmodule DealAgent.Agents.ShoppingAgent do
  @moduledoc """
  Interprets natural-language shopping requests into structured
  Shopping.Intent values using BeamAgent.
  """

  alias DealAgent.Shopping.IntentConverter

  @spec interpret(String.t()) ::
          {:ok, DealAgent.Shopping.Intent.t()}
          | {:error, term()}
  def interpret(input) when is_binary(input) do
    interpret(input, [])
  end

  @spec interpret(String.t(), keyword()) ::
          {:ok, DealAgent.Shopping.Intent.t()}
          | {:error, term()}
  def interpret(input, opts) do
    llm =
      opts
      |> Keyword.get_lazy(:llm, &default_llm/0)
      |> normalize_llm()

    result = interpret_with_llm(input, llm)

    case result do
      {:error, {:openai_request_failed, %Req.TransportError{}}} ->
        case DealAgent.Shopping.CommandParser.parse(input) do
          {:ok, intent} -> {:ok, intent}
          _ -> result
        end

      _ ->
        result
    end
  end

  defp interpret_with_llm(input, llm) do
    with :ok <- validate_llm(llm),
         {:ok, run} <- run_agent(input, llm),
         {:ok, payload} <- extract_payload(run),
         {:ok, intent} <- IntentConverter.convert(payload, input) do
      {:ok, intent}
    else
      {:error, %BeamAgent.Run{error: error}} when not is_nil(error) -> {:error, error}
      other -> other
    end
  end

  defp run_agent(input, llm) do
    reference = make_ref()

    result =
      BeamAgent.API.run(
        input,
        llm:
          {DealAgent.LLM.CheckedClient, [client: llm, recipient: self(), reference: reference]},
        tools: DealAgent.Tools.Registry.tools(),
        verification: [
          required_tools: [:capture_intent]
        ],
        guardrails: [
          max_iterations: 3,
          max_tool_calls: 1,
          max_execution_time_ms: 100_000
        ]
      )

    receive do
      {:shopping_llm_error, ^reference, reason} -> {:error, reason}
    after
      0 -> result
    end
  end

  # `:llm` may be given as `{module, opts}` or a bare `module`.
  defp normalize_llm({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp normalize_llm(module) when is_atom(module), do: {module, []}

  defp validate_llm({DealAgent.LLM.OpenAI, opts}) do
    case Keyword.get(opts, :api_key) do
      key when is_binary(key) and byte_size(key) > 0 -> :ok
      _ -> {:error, :missing_openai_api_key}
    end
  end

  defp validate_llm(_llm), do: :ok

  defp default_llm do
    Application.get_env(:deal_agent, :shopping_agent_llm) || openai_llm()
  end

  defp openai_llm do
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

  defp extract_payload(run) do
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
