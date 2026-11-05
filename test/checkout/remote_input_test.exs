defmodule DealAgent.Checkout.RemoteInputTest do
  use ExUnit.Case, async: true
  alias DealAgent.Checkout.RemoteInput

  test "permits only bounded pointer and keyboard input, never URLs or scripts" do
    for input <- [
          %{"type" => "frame"},
          %{"type" => "click", "x" => 10, "y" => 20},
          %{"type" => "scroll", "delta" => -600},
          %{"type" => "key", "key" => "Tab"},
          %{"type" => "text", "text" => "Demo address"},
          %{"type" => "tab", "index" => 1}
        ],
        do: assert(RemoteInput.valid?(input))

    for input <- [
          %{"type" => "navigate", "url" => "http://localhost"},
          %{"type" => "evaluate", "script" => "document.cookie"},
          %{"type" => "click", "x" => -1, "y" => 5},
          %{"type" => "click", "x" => 1024, "y" => 5},
          %{"type" => "text", "text" => String.duplicate("x", 2049)},
          %{"type" => "key", "key" => "F12"},
          %{"type" => "frame", "extra" => "unbounded"},
          %{"type" => "text", "text" => "text", "extra" => "unbounded"}
        ],
        do: refute(RemoteInput.valid?(input))
  end
end
