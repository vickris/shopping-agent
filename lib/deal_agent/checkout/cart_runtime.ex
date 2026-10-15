defmodule DealAgent.Checkout.CartRuntime do
  @moduledoc "Owns the isolated store browser process; credentials never enter its environment."
  def start do
    with node when is_binary(node) <- System.find_executable("node") do
      script = Application.app_dir(:deal_agent, "priv/carrefour_browser/cart.mjs")

      {:ok,
       Port.open({:spawn_executable, String.to_charlist(node)}, [
         :binary,
         :exit_status,
         {:line, 65_536},
         {:args, [String.to_charlist(script)]},
         {:env, [{~c"OPENAI_API_KEY", false}, {~c"ANTHROPIC_API_KEY", false}]}
       ])}
    else
      _ -> {:error, :browser_dependency_missing}
    end
  rescue
    _ -> {:error, :browser_start_failed}
  end
end
