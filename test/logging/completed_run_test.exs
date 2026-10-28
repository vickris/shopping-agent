defmodule DealAgent.CompletedRunTest do
  use ExUnit.Case, async: false

  test "provider usage survives the intent loop and sanitized PostgreSQL history" do
    previous = Application.get_env(:beam_agent, :trace_store)

    options =
      DealAgent.Repo.config() |> Keyword.take([:hostname, :port, :database, :username, :password])

    {:ok, connection} = Postgrex.start_link(options)

    Application.put_env(:beam_agent, :trace_store,
      adapter: BeamAgent.Trace.Store.Postgres,
      retention_ms: :timer.hours(1),
      options: [connection: connection]
    )

    try do
      plug = fn conn ->
        Req.Test.json(conn, %{
          "usage" => %{"input_tokens" => 123, "output_tokens" => 17},
          "output" => [
            %{
              "type" => "function_call",
              "call_id" => "test_intent",
              "name" => "capture_intent",
              "arguments" => Jason.encode!(%{action: "add_item", name: "milk"})
            }
          ]
        })
      end

      assert {:ok, run} =
               BeamAgent.API.run("private shopping request",
                 llm:
                   {DealAgent.LLM.OpenAI,
                    [
                      api_key: "fixture",
                      tools: [DealAgent.Tools.CaptureIntent],
                      request_options: [plug: plug]
                    ]},
                 tools: DealAgent.Tools.Registry.tools(),
                 verification: [required_tools: [:capture_intent]],
                 guardrails: [max_iterations: 3, max_tool_calls: 1]
               )

      try do
        assert {:ok, %{summary: summary, trace: trace}} =
                 BeamAgent.API.lookup_completed(run.run_key)

        assert summary.input_tokens == 123
        assert summary.output_tokens == 17
        assert summary.usage_status == :reported
        assert summary.cost_status == :unknown_price
        assert summary.verification_status == :passed
        refute inspect({summary, trace}) =~ "private shopping request"
        refute inspect({summary, trace}) =~ "milk"
      after
        Postgrex.query!(connection, "DELETE FROM beam_agent_runs WHERE run_key = $1", [
          run.run_key
        ])
      end
    after
      if previous,
        do: Application.put_env(:beam_agent, :trace_store, previous),
        else: Application.delete_env(:beam_agent, :trace_store)

      GenServer.stop(connection)
    end
  end
end
