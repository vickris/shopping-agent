defmodule DealAgent.LLM.CheckedClient do
  @moduledoc "Adapts provider errors to BeamAgent's reply/tool-call-only callback contract."
  @behaviour BeamAgent.LLM.Client

  @impl true
  def chat(messages, opts) do
    {client, client_options} = Keyword.fetch!(opts, :client)

    case client.chat(messages, client_options) do
      {:error, reason} ->
        send(
          Keyword.fetch!(opts, :recipient),
          {:shopping_llm_error, Keyword.fetch!(opts, :reference), reason}
        )

        # No tool was called: required-tool verification still rejects this run.
        {:reply, "Shopping interpretation failed."}

      response ->
        response
    end
  end
end
