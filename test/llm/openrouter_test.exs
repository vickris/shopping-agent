defmodule DealAgent.LLM.OpenRouterTest do
  use ExUnit.Case, async: true
  alias DealAgent.LLM.OpenAI

  test "OpenRouter uses its own host, key and model with the same intent tool and reported usage" do
    plug = fn conn ->
      assert conn.host == "openrouter.ai"
      assert conn.request_path == "/api/v1/responses"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer router-fixture"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(body)
      assert body["model"] == "openai/gpt-4.1-mini"
      assert body["tool_choice"] == "required"
      assert body["parallel_tool_calls"] == false
      assert body["provider"]["require_parameters"] == true
      refute Map.has_key?(body, "reasoning")
      assert [%{"name" => "capture_intent", "strict" => true}] = body["tools"]

      Req.Test.json(conn, %{
        "output" => [
          %{
            "type" => "function_call",
            "call_id" => "router_1",
            "name" => "capture_intent",
            "arguments" =>
              Jason.encode!(%{action: "add_item", name: "milk", quantity: "2", unit: "litre"})
          }
        ],
        "usage" => %{"input_tokens" => 100, "output_tokens" => 20}
      })
    end

    opts = [
      provider: :openrouter,
      api_key: "router-fixture",
      model: "openai/gpt-4.1-mini",
      tools: [DealAgent.Tools.CaptureIntent],
      request_options: [plug: plug]
    ]

    assert {:tool_call, _, %{input_tokens: 100, output_tokens: 20}} =
             OpenAI.chat([%{role: :user, content: "milk"}], opts)

    assert {:ok, intent} =
             DealAgent.Agents.ShoppingAgent.interpret("2 litres of milk", llm: {OpenAI, opts})

    assert intent.item.name == "milk"
  end

  test "missing OpenRouter key is caught before making requests" do
    assert {:error, :missing_openrouter_api_key} =
             DealAgent.Agents.ShoppingAgent.interpret("milk",
               llm: {OpenAI, [provider: :openrouter]}
             )
  end

  test "OpenRouter insufficient credit errors retain their provider and are not retried" do
    parent = self()

    plug = fn conn ->
      send(parent, :requested)
      conn |> Plug.Conn.put_status(402) |> Req.Test.json(%{"error" => %{"code" => 402}})
    end

    assert {:error, {:openrouter_http_error, 402, _}} =
             DealAgent.Agents.ShoppingAgent.interpret("milk",
               llm:
                 {OpenAI,
                  [provider: :openrouter, api_key: "fixture", request_options: [plug: plug]]}
             )

    assert_receive :requested
    refute_receive :requested
  end
end
