defmodule DealAgent.Delivery.RemoteCheckoutTest do
  use ExUnit.Case, async: false
  alias DealAgent.Delivery.Sessions

  setup do
    old = Application.get_env(:deal_agent, :remote_checkout_enabled)
    Application.put_env(:deal_agent, :remote_checkout_enabled, true)

    on_exit(fn ->
      if is_nil(old),
        do: Application.delete_env(:deal_agent, :remote_checkout_enabled),
        else: Application.put_env(:deal_agent, :remote_checkout_enabled, old)
    end)

    :ok
  end

  test "only the live owner can control a reserved cart; closing destroys access" do
    owner = self()
    assert {:ok, id} = Sessions.start(owner, "carrefour", "Remote demo")
    assert_receive {:delivery_event, ^id, %{"type" => "setup"}}, 3000
    assert {:error, :remote_unavailable} = Sessions.remote(owner, id, %{"type" => "frame"})
    assert :ok = Sessions.command(owner, id, "confirm")
    assert_receive {:delivery_event, ^id, %{"type" => "confirmed"}}, 3000
    assert :ok = Sessions.cart(owner, id, "carrefour", %{delivery_session_id: id, products: []})
    assert_receive {:cart_event, ^id, %{"verified" => true}}, 3000
    # Supplying a known owner PID or session ID is not enough: caller must own it.
    assert {:error, :remote_unavailable} =
             Task.async(fn -> Sessions.remote(owner, id, %{"type" => "frame"}) end)
             |> Task.await()

    assert {:ok, %{"image" => "fixture"}} = Sessions.remote(owner, id, %{"type" => "frame"})

    assert {:error, :remote_unavailable} =
             Sessions.remote(owner, id, %{"type" => "evaluate", "script" => "document.cookie"})

    assert {:error, :session_busy} = Sessions.search(owner, id, "carrefour", "milk")
    Application.put_env(:deal_agent, :remote_checkout_enabled, false)
    assert {:error, :remote_unavailable} = Sessions.remote(owner, id, %{"type" => "frame"})
    Application.put_env(:deal_agent, :remote_checkout_enabled, true)
    assert :ok = Sessions.command(owner, id, "close")
    assert {:error, :remote_unavailable} = Sessions.remote(owner, id, %{"type" => "frame"})
  end

  test "expiry and owner disconnect close private checkout sessions" do
    assert {:ok, id} = Sessions.start(self(), "carrefour", "Expiry")
    send(Sessions, {:expiry, id})
    assert {:error, :remote_unavailable} = Sessions.remote(self(), id, %{"type" => "frame"})

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert {:ok, disconnected} = Sessions.start(owner, "carrefour", "Disconnect")
    ref = Process.monitor(owner)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^owner, _}
    # The GenServer's monitor notification is asynchronous.
    wait_closed(disconnected)
  end

  test "an uncertain remote action closes its own session without retrying input" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, id} = Sessions.start(self(), "carrefour", "Remote timeout")
        :ok = Sessions.command(self(), id, "confirm")

        receive do
          {:delivery_event, ^id, %{"type" => "confirmed"}} -> :ok
        end

        :ok = Sessions.cart(self(), id, "carrefour", %{delivery_session_id: id, products: []})

        receive do
          {:cart_event, ^id, %{"verified" => true}} -> :ok
        end

        send(parent, {:reserved, id})

        result =
          Sessions.remote(self(), id, %{"type" => "text", "text" => "sensitive-demo-input"})

        send(parent, {:remote_result, result})
      end)

    owner_ref = Process.monitor(owner)
    assert_receive {:reserved, id}, 3000
    pending = wait_pending(id)
    send(Sessions, {:remote_timeout, id, pending})
    assert_receive {:remote_result, {:error, :remote_unavailable}}, 3000
    refute Map.has_key?(:sys.get_state(Sessions), id)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, _}, 3000
  end

  defp wait_pending(id, attempts \\ 100)
  defp wait_pending(_, 0), do: flunk("remote input was not dispatched")

  defp wait_pending(id, attempts) do
    case :sys.get_state(Sessions)[id] do
      %{remote_pending: {request_id, _, _}} ->
        request_id

      _ ->
        Process.sleep(10)
        wait_pending(id, attempts - 1)
    end
  end

  defp wait_closed(id, attempts \\ 100)
  defp wait_closed(_id, 0), do: flunk("private session did not close")

  defp wait_closed(id, attempts) do
    if Map.has_key?(:sys.get_state(Sessions), id) do
      Process.sleep(10)
      wait_closed(id, attempts - 1)
    end
  end
end
