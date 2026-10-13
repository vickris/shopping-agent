defmodule DealAgent.Supermarkets.SearchQueueTest do
  use ExUnit.Case, async: false
  alias DealAgent.Supermarkets.SearchQueue

  test "same store waits FIFO while another store proceeds independently" do
    parent = self()

    first =
      Task.async(fn ->
        SearchQueue.run(:carrefour, fn ->
          send(parent, {:started, self()})

          receive do
            :release -> :first
          end
        end)
      end)

    assert_receive {:started, worker}

    second =
      Task.async(fn ->
        SearchQueue.run(:carrefour, fn ->
          send(parent, :second_started)
          :second
        end)
      end)

    # Synchronize on the server mailbox rather than relying on timing.
    wait_pending(DealAgent.CarrefourQueue, 1)

    third =
      Task.async(fn ->
        SearchQueue.run(:carrefour, fn ->
          send(parent, :third_started)
          :third
        end)
      end)

    wait_pending(DealAgent.CarrefourQueue, 2)
    assert :other_store == SearchQueue.run(:quickmart, fn -> :other_store end)
    refute_received :second_started
    send(worker, :release)
    assert :first == Task.await(first)
    assert_receive :second_started
    assert_receive :third_started
    assert :second == Task.await(second)
    assert :third == Task.await(third)
  end

  test "cancelled caller releases the store and worker failure does not stall the queue" do
    parent = self()

    caller =
      spawn(fn ->
        SearchQueue.run(:naivas, fn ->
          send(parent, {:active, self()})

          receive do
            :never -> :ok
          end
        end)
      end)

    assert_receive {:active, worker}
    monitor = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}

    assert {:error, :browser_search_failed} ==
             SearchQueue.run(:naivas, fn -> exit(:test_failure) end)

    assert :recovered == SearchQueue.run(:naivas, fn -> :recovered end)
  end

  test "expired workers and cancelled pending jobs do not hold up later jobs" do
    parent = self()

    first =
      Task.async(fn ->
        SearchQueue.run(:naivas, fn ->
          send(parent, :running)

          receive do
            :never -> :ok
          end
        end)
      end)

    assert_receive :running
    caller = spawn(fn -> SearchQueue.run(:naivas, fn -> send(parent, :cancelled_job_ran) end) end)
    wait_pending(DealAgent.NaivasQueue, 1)
    monitor = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, _}
    wait_pending(DealAgent.NaivasQueue, 0)
    job = :sys.get_state(DealAgent.NaivasQueue).active
    send(DealAgent.NaivasQueue, {:expired, job.token})
    assert {:error, :browser_timeout} == Task.await(first)
    assert :next == SearchQueue.run(:naivas, fn -> :next end)
    refute_received :cancelled_job_ran
  end

  defp wait_pending(name, count, attempts \\ 100)

  defp wait_pending(name, count, attempts) when attempts > 0 do
    if :queue.len(:sys.get_state(name).pending) != count do
      Process.sleep(1)
      wait_pending(name, count, attempts - 1)
    end
  end

  defp wait_pending(_, _, 0), do: flunk("job did not enter the queue")
end
