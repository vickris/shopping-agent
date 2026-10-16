defmodule DealAgent.Logging.AgentLoggingTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias DealAgent.Agents.ShoppingAgent
  alias DealAgent.Logging.JSONFormatter

  setup do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)
    :ok
  end

  test "real agent runs emit correlated JSON lifecycle events without shopping content" do
    secret = "Add two litres of milk"

    logs =
      capture_log([level: :info, format: {JSONFormatter, :format}, metadata: :all], fn ->
        assert {:ok, _} = ShoppingAgent.interpret(secret, llm: {TestLLM, []})
        assert {:error, _} = ShoppingAgent.interpret("hello world", llm: {TestLLM, []})
      end)

    records = logs |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    starts = Enum.filter(records, &(&1["beam_agent_event"] == "beam_agent.run.start"))
    stops = Enum.filter(records, &(&1["beam_agent_event"] == "beam_agent.run.stop"))
    assert length(starts) == 2
    assert length(stops) == 2

    assert MapSet.new(Enum.map(starts, & &1["run_key"])) ==
             MapSet.new(Enum.map(stops, & &1["run_key"]))

    assert Enum.any?(stops, &(&1["outcome"] == "ok" && &1["verification_status"] == "passed"))
    assert Enum.any?(stops, &(&1["outcome"] == "error" && &1["verification_status"] == "failed"))
    assert Enum.all?(stops, &(is_number(&1["duration_ms"]) && &1["duration_ms"] >= 0))
    refute logs =~ secret
    refute logs =~ "hello world"
    refute logs =~ "capture_intent"
  end

  test "formatter excludes arbitrary inherited metadata and escapes multiline messages" do
    log =
      JSONFormatter.format(:info, "one\ntwo", {{2026, 10, 16}, {12, 0, 0, 123}},
        request_id: "request-1",
        prompt: "private",
        api_key: "secret",
        run_id: make_ref()
      )

    record = log |> IO.iodata_to_binary() |> Jason.decode!()
    assert record["timestamp"] == "2026-10-16T12:00:00.123Z"
    assert record["message"] == "one\ntwo"
    assert record["request_id"] == "request-1"
    refute Map.has_key?(record, "prompt")
    refute Map.has_key?(record, "api_key")
    refute Map.has_key?(record, "run_id")
  end
end
