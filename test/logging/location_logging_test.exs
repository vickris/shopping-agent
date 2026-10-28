defmodule DealAgent.Logging.LocationLoggingTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias DealAgent.Delivery.Sessions

  test "failed location records keep only bounded stage and error metadata" do
    assert {:ok, id} = Sessions.start(self(), "carrefour", "Syokimau")
    assert_receive {:delivery_event, ^id, %{"type" => "setup"}}, 3000
    port = :sys.get_state(Sessions)[id].port

    logs =
      capture_log([format: {DealAgent.Logging.JSONFormatter, :format}, metadata: :all], fn ->
        for {stage, error} <- [
              {"saving_location", "location_timeout"},
              {"private address", "private token"}
            ] do
          event = %{
            "type" => "setup",
            "status" => "unavailable",
            "stage" => stage,
            "error" => error,
            "message" => "private detail"
          }

          send(Sessions, {port, {:data, {:eol, Jason.encode!(event)}}})

          assert_receive {:delivery_event, ^id, %{"type" => "setup", "status" => "unavailable"}},
                         3000
        end
      end)

    records = logs |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    assert Enum.any?(
             records,
             &(&1["message"] == "supermarket.location.failed" &&
                 &1["location_stage"] == "saving_location" &&
                 &1["error_type"] == "location_timeout")
           )

    assert Enum.any?(
             records,
             &(&1["location_stage"] == "unknown" && &1["error_type"] == "location_setup_failed")
           )

    refute logs =~ "private"
    assert :ok = Sessions.command(self(), id, "close")
  end
end
