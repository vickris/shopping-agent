defmodule DealAgent.Checkout.CartJobsTest do
  use ExUnit.Case, async: false
  alias DealAgent.Checkout.CartJobs

  test "delivers verified notification, prevents duplicate carts and checks command ownership" do
    assert {:ok, id} = CartJobs.start(self(), %{products: []})
    assert_receive {:cart_event, ^id, %{"status" => "ready", "verified" => true}}, 3000
    send(CartJobs, {:timeout, id})
    assert Map.has_key?(:sys.get_state(CartJobs), id)
    assert {:error, :cart_already_open} = CartJobs.start(self(), %{})

    stranger =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert {:error, :unknown_cart} = CartJobs.command(stranger, id, "close")
    send(stranger, :stop)
    assert :ok = CartJobs.command(self(), id, "close")
    assert_receive {:cart_event, ^id, %{"status" => "closed"}}, 3000
  end
end
