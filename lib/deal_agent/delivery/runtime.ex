defmodule DealAgent.Delivery.Runtime do
  @moduledoc false
  def start do
    script = Application.app_dir(:deal_agent, "priv/carrefour_browser/delivery_session.mjs")

    case System.find_executable("node") do
      nil ->
        {:error, :browser_dependency_missing}

      node ->
        {:ok,
         Port.open({:spawn_executable, String.to_charlist(node)}, [
           :binary,
           :exit_status,
           {:line, 4_194_304},
           {:args, [String.to_charlist(script)]},
           {:env, [{~c"OPENAI_API_KEY", false}, {~c"ANTHROPIC_API_KEY", false}]}
         ])}
    end
  rescue
    _ -> {:error, :browser_start_failed}
  end
end
