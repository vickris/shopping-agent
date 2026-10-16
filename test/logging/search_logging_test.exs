defmodule DealAgent.Logging.SearchLoggingTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias DealAgent.Supermarkets.SearchQueue
  alias DealAgent.Logging.JSONFormatter

  setup do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)
    :ok
  end

  test "search events correlate results and bounded failures without leaking contents" do
    logs =
      capture_log([format: {JSONFormatter, :format}, metadata: :all], fn ->
        assert {:ok, [_]} =
                 SearchQueue.run(:carrefour, fn -> {:ok, [%{name: "private product"}]} end)

        assert {:ok, []} = SearchQueue.run(:quickmart, fn -> {:ok, []} end)

        assert {:error, _} =
                 SearchQueue.run(:naivas, fn -> {:error, {:private, "secret query"}} end)

        assert {:error, _} =
                 SearchQueue.run(:carrefour, fn -> {:error, {:browser_http_error, 503}} end)

        assert {:error, :browser_search_failed} =
                 SearchQueue.run(:naivas, fn -> raise "private exception" end)
      end)

    events = records(logs)
    groups = Enum.group_by(events, & &1["search_id"])
    assert map_size(groups) == 5

    for {id, records} <- groups do
      assert is_binary(id)

      assert Enum.map(records, & &1["search_event"]) ==
               [
                 "supermarket.search.queued",
                 "supermarket.search.start",
                 "supermarket.search.stop"
               ]

      terminal = List.last(records)
      assert terminal["duration_ms"] >= 0
      assert terminal["queue_wait_ms"] >= 0
    end

    assert Enum.any?(events, &(&1["product_count"] == 1))
    assert Enum.any?(events, &(&1["product_count"] == 0 && &1["outcome"] == "ok"))
    assert Enum.any?(events, &(&1["error_type"] == "search_failed"))
    assert Enum.any?(events, &(&1["http_status"] == 503))
    assert Enum.any?(events, &(&1["error_type"] == "worker_exit"))
    refute logs =~ "private product"
    refute logs =~ "secret query"
    refute logs =~ "private exception"
  end

  test "queued cancellation and active timeout each emit one terminal event" do
    parent = self()

    logs =
      capture_log([format: {JSONFormatter, :format}, metadata: :all], fn ->
        first =
          Task.async(fn ->
            SearchQueue.run(:naivas, fn ->
              send(parent, :started)

              receive do
                :release -> {:ok, []}
              end
            end)
          end)

        assert_receive :started
        pending = spawn(fn -> SearchQueue.run(:naivas, fn -> flunk("cancelled work ran") end) end)
        wait_until(fn -> :queue.len(:sys.get_state(DealAgent.NaivasQueue).pending) == 1 end)
        Process.exit(pending, :kill)
        wait_until(fn -> :queue.len(:sys.get_state(DealAgent.NaivasQueue).pending) == 0 end)
        job = :sys.get_state(DealAgent.NaivasQueue).active
        send(DealAgent.NaivasQueue, {:expired, job.token})
        assert {:error, :browser_timeout} = Task.await(first)
        # The worker DOWN/old timeout must not emit a second terminal event.
        send(DealAgent.NaivasQueue, {:expired, job.token})
        :sys.get_state(DealAgent.NaivasQueue)
      end)

    events = records(logs)
    stops = Enum.filter(events, &(&1["search_event"] == "supermarket.search.stop"))
    assert length(stops) == 2
    assert Enum.any?(stops, &(&1["phase"] == "queued" && &1["outcome"] == "cancelled"))
    assert Enum.any?(stops, &(&1["phase"] == "active" && &1["error_type"] == "browser_timeout"))
  end

  defp records(logs) do
    logs
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
    |> Enum.filter(&Map.has_key?(&1, "search_event"))
  end

  defp wait_until(check, attempts \\ 100)
  defp wait_until(_, 0), do: flunk("queue did not reach expected state")

  defp wait_until(check, attempts) do
    unless check.() do
      Process.sleep(1)
      wait_until(check, attempts - 1)
    end
  end
end
