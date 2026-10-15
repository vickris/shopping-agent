defmodule DealAgent.Checkout.CartJobsTest do
  use ExUnit.Case, async: false
  alias DealAgent.Checkout.CartJobs

  test "keeps store jobs independent and resumes a paused cart only once" do
    assert {:ok, quickmart} = CartJobs.start(self(), %{store: "quickmart", products: []})
    assert_receive {:cart_event, ^quickmart, %{"status" => "awaiting_input"}}, 3000
    send(CartJobs, {:timeout, quickmart})
    assert Map.has_key?(:sys.get_state(CartJobs), quickmart)
    assert {:ok, carrefour} = CartJobs.start(self(), %{store: "carrefour", products: []})
    assert_receive {:cart_event, ^carrefour, %{"status" => "ready"}}, 3000
    assert :ok = CartJobs.command(self(), quickmart, "resume")
    assert {:error, :not_paused} = CartJobs.command(self(), quickmart, "resume")

    assert_receive {:cart_event, ^quickmart,
                    %{"status" => "needs_attention", "verified" => true}},
                   3000

    for id <- [quickmart, carrefour] do
      assert :ok = CartJobs.command(self(), id, "close")
      assert_receive {:cart_event, ^id, %{"status" => "closed"}}, 3000
    end
  end

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
