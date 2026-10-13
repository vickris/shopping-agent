defmodule DealAgent.Checkout.TestRuntime do
  def start do
    script = Path.expand("test/support/cart_runtime.mjs")

    {:ok,
     Port.open({:spawn_executable, System.find_executable("node") |> String.to_charlist()}, [
       :binary,
       :exit_status,
       {:line, 65536},
       {:args, [String.to_charlist(script)]}
     ])}
  end
end
