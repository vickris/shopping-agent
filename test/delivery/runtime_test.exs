defmodule DealAgent.Delivery.RuntimeTest do
  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "runtime starts through Phoenix's symlinked priv path", %{tmp_dir: dir} do
    script = Path.expand("../../priv/carrefour_browser/delivery_session.mjs", __DIR__)
    link = Path.join(dir, "delivery-session.mjs")
    File.ln_s!(script, link)
    node = System.find_executable("node")

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(node)},
        [:binary, :exit_status, {:line, 65536}, {:args, [String.to_charlist(link)]}]
      )

    # Invalid setup stops before loading any browser or opening a network connection.
    Port.command(port, Jason.encode!(%{store: "invalid", area: "Syokimau"}) <> "\n")
    assert_receive {^port, {:data, {:eol, line}}}, 3000
    assert %{"type" => "setup_error"} = Jason.decode!(line)
    assert_receive {^port, {:exit_status, 1}}, 3000
  end
end
