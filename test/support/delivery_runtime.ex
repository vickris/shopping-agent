defmodule DealAgent.Delivery.TestRuntime do
  def start do
    script = Path.expand("delivery_runtime.mjs", __DIR__)

    {:ok,
     Port.open(
       {:spawn_executable, String.to_charlist(System.find_executable("node"))},
       [:binary, :exit_status, {:line, 4_194_304}, {:args, [String.to_charlist(script)]}]
     )}
  end
end
