defmodule DealAgent.Delivery.SessionsTest do
  use ExUnit.Case, async: false
  alias DealAgent.Delivery.Sessions

  test "each store keeps its own confirmed session through search and cart handoff" do
    for store <- ~w(carrefour quickmart naivas foodplus) do
      owner = self()
      assert {:ok, id} = Sessions.start(owner, store, "Syokimau")
      assert_receive {:delivery_event, ^id, %{"type" => "setup"}}, 3000
      assert {:error, :location_unconfirmed} = Sessions.search(owner, id, store, "milk")
      assert :ok = Sessions.command(owner, id, "confirm")
      assert_receive {:delivery_event, ^id, %{"type" => "confirmed"}}, 3000
      assert {:ok, html} = Sessions.search(owner, id, store, "milk")
      assert html =~ "Milk 500ml"
      assert {:error, :location_unconfirmed} = Sessions.search(owner, id, "other", "milk")
      assert {:error, :session_unavailable} = Sessions.command(spawn(fn -> :ok end), id, "open")

      assert {:error, :location_unconfirmed} =
               Sessions.cart(owner, id, store, %{delivery_session_id: "stale"})

      assert :ok = Sessions.cart(owner, id, store, %{delivery_session_id: id, products: []})

      assert_receive {:cart_event, ^id, %{"status" => "needs_attention", "verified" => true}},
                     3000

      assert :ok = Sessions.command(owner, id, "open")
      assert {:error, :session_unavailable} = Sessions.command(owner, id, "open")
      assert {:error, :session_busy} = Sessions.search(owner, id, store, "milk")
      assert_receive {:delivery_event, ^id, %{"type" => "window", "status" => "opened"}}, 3000
      assert {:error, :session_busy} = Sessions.search(owner, id, store, "milk")
      assert :ok = Sessions.command(owner, id, "close")
      assert_receive {:delivery_event, ^id, %{"type" => "closed"}}, 3000
      assert {:error, :location_unconfirmed} = Sessions.search(owner, id, store, "milk")
    end
  end

  test "failed window handoff preserves the cart reservation and permits another open" do
    assert {:ok, id} = Sessions.start(self(), "carrefour", "Window failure")
    assert :ok = Sessions.command(self(), id, "confirm")
    assert_receive {:delivery_event, ^id, %{"type" => "confirmed"}}, 3000
    assert :ok = Sessions.cart(self(), id, "carrefour", %{delivery_session_id: id, products: []})
    assert_receive {:cart_event, ^id, %{"verified" => true}}, 3000

    for _ <- 1..2 do
      assert :ok = Sessions.command(self(), id, "open")
      assert_receive {:delivery_event, ^id, %{"type" => "window", "status" => "failed"}}, 3000
      assert :sys.get_state(Sessions)[id].busy == :handoff
      assert :sys.get_state(Sessions)[id].confirmed
      assert {:error, :session_busy} = Sessions.search(self(), id, "carrefour", "milk")
    end

    assert :ok = Sessions.command(self(), id, "close")
  end

  test "automatic location failures retry in their own session without manual confirmation" do
    point = %{"latitude" => -1.367, "longitude" => 36.936, "accuracy" => 100}
    assert {:ok, id} = Sessions.start(self(), "naivas", "Automatic retry", point)
    assert_receive {:delivery_event, ^id, %{"type" => "setup", "status" => "unavailable"}}, 3000
    assert {:error, :automatic_location} = Sessions.command(self(), id, "confirm")
    assert {:error, :session_unavailable} = Sessions.command(spawn(fn -> :ok end), id, "locate")
    assert :ok = Sessions.command(self(), id, "locate")
    assert {:error, :session_unavailable} = Sessions.command(self(), id, "locate")
    assert {:error, :location_unconfirmed} = Sessions.search(self(), id, "naivas", "milk")

    assert_receive {:delivery_event, ^id,
                    %{"type" => "confirmed", "location" => %{"confirmation" => "geolocation"}}},
                   3000

    assert {:ok, _} = Sessions.search(self(), id, "naivas", "milk")
    assert :ok = Sessions.command(self(), id, "close")
  end

  test "location changes invalidate confirmation without default-area fallback" do
    assert {:ok, id} = Sessions.start(self(), "carrefour", "Syokimau")
    assert :ok = Sessions.command(self(), id, "confirm")
    assert_receive {:delivery_event, ^id, %{"type" => "confirmed"}}, 3000
    assert {:error, :location_changed} = Sessions.search(self(), id, "carrefour", "changed")
    assert_receive {:delivery_event, ^id, %{"type" => "invalidated"}}, 3000
    assert {:error, :location_unconfirmed} = Sessions.search(self(), id, "carrefour", "milk")
    assert_receive {:delivery_event, ^id, %{"type" => "closed"}}, 3000
    assert {:error, :session_unavailable} = Sessions.command(self(), id, "confirm")
  end

  test "session expiry releases an in-flight search and clears its owner controls" do
    owner = self()
    assert {:ok, id} = Sessions.start(owner, "carrefour", "Syokimau")
    assert :ok = Sessions.command(owner, id, "confirm")
    assert_receive {:delivery_event, ^id, %{"type" => "confirmed"}}, 3000
    task = Task.async(fn -> Sessions.search(owner, id, "carrefour", "slow") end)
    wait_until(fn -> match?({:search, _, _, _, _}, :sys.get_state(Sessions)[id].busy) end)
    send(Sessions, {:expiry, id})
    assert {:error, :location_unconfirmed} = Task.await(task)
    assert_receive {:delivery_event, ^id, %{"type" => "closed"}}, 3000
  end

  defp wait_until(check, attempts \\ 100)
  defp wait_until(_, 0), do: flunk("session did not reach expected state")

  defp wait_until(check, attempts) do
    unless check.() do
      Process.sleep(1)
      wait_until(check, attempts - 1)
    end
  end
end
