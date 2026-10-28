defmodule DealAgent.LLM.OpenAITest do
  use ExUnit.Case, async: true

  alias DealAgent.Agents.ShoppingAgent
  alias DealAgent.LLM.OpenAI
  alias DealAgent.Tools.CaptureIntent

  defmodule ClosedAdapter do
    def run(request) do
      {request, %Req.TransportError{reason: :closed}}
    end
  end

  test "bare shopping request captures intent once and completes the BeamAgent run" do
    parent = self()

    plug = fn conn ->
      assert conn.request_path == "/v1/responses"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(body)
      assert body["tool_choice"] == "required"
      assert body["parallel_tool_calls"] == false
      assert body["instructions"] =~ "2 litres of milk"
      assert body["input"] == [%{"role" => "user", "content" => "2 litres of milk"}]
      assert [%{"name" => "capture_intent", "strict" => true}] = body["tools"]
      send(parent, :openai_request)

      Req.Test.json(conn, %{
        "output" => [
          %{
            "type" => "function_call",
            "call_id" => "call_1",
            "name" => "capture_intent",
            "arguments" =>
              Jason.encode!(%{action: "add_item", name: "milk", quantity: "2", unit: "litre"})
          }
        ]
      })
    end

    assert {:ok, intent} =
             ShoppingAgent.interpret("2 litres of milk",
               llm:
                 {OpenAI,
                  [api_key: "test-key", tools: [CaptureIntent], request_options: [plug: plug]]}
             )

    assert intent.action == :add_item
    assert intent.item.name == "milk"
    assert intent.item.unit == :litre
    assert Decimal.equal?(intent.item.quantity, Decimal.new("2"))
    assert_receive :openai_request
    refute_receive :openai_request
  end

  test "the existing intent capture preserves the requested supermarkets" do
    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(body)
      assert [%{"name" => "capture_intent", "parameters" => schema}] = body["tools"]
      assert "supermarkets" in schema["required"]
      assert schema["properties"]["supermarkets"]["type"] == ["array", "null"]

      Req.Test.json(conn, %{
        "output" => [
          %{
            "type" => "function_call",
            "call_id" => "scope_1",
            "name" => "capture_intent",
            "arguments" =>
              Jason.encode!(%{
                action: "add_items",
                items: Enum.map(~w(milk ice water), &%{name: &1, quantity: nil, unit: nil}),
                supermarkets: ["naivas", "carrefour"],
                name: nil,
                quantity: nil,
                unit: nil
              })
          }
        ]
      })
    end

    assert {:ok, intent} =
             ShoppingAgent.interpret("Milk, ice and water. Compare Naivas and Carrefour.",
               llm:
                 {OpenAI,
                  [api_key: "test", tools: [CaptureIntent], request_options: [plug: plug]]}
             )

    assert intent.supermarkets == ["naivas", "carrefour"]
    assert Enum.map(intent.items, & &1.name) == ~w(milk ice water)
  end

  test "tool results finish locally without issuing a second model request" do
    assert {:reply, "Shopping intent captured.", %{input_tokens: 0, output_tokens: 0}} =
             OpenAI.chat(
               [%{role: :tool, type: :tool_result, call_id: "call_1", content: "captured"}],
               []
             )
  end

  test "passes provider token usage to BeamAgent without response details" do
    plug = fn conn ->
      Req.Test.json(conn, %{
        "output" => [
          %{"type" => "message", "content" => [%{"type" => "output_text", "text" => "Hello"}]}
        ],
        "usage" => %{
          "input_tokens" => 123,
          "output_tokens" => 17,
          "output_tokens_details" => %{"reasoning_tokens" => 8}
        }
      })
    end

    assert {:reply, "Hello", %{input_tokens: 123, output_tokens: 17}} =
             OpenAI.chat([%{role: :user, content: "hello"}],
               api_key: "test",
               request_options: [plug: plug]
             )
  end

  test "missing API key is a configuration error before starting a model run" do
    assert {:error, :missing_openai_api_key} =
             ShoppingAgent.interpret("2 litres of milk", llm: {OpenAI, [api_key: nil]})
  end

  test "closed connections retry once then recover a simple command locally" do
    assert {:ok, intent} =
             ShoppingAgent.interpret("2 litres of Brookside milk",
               llm:
                 {OpenAI,
                  [
                    api_key: "test",
                    tools: [CaptureIntent],
                    request_options: [adapter: ClosedAdapter, retry_delay: 0]
                  ]}
             )

    assert intent.item.name == "Brookside milk"
    assert intent.item.unit == :litre
    assert Decimal.equal?(intent.item.quantity, "2")
  end

  test "transport errors retain their cause for ambiguous commands" do
    assert {:error, {:openai_request_failed, %Req.TransportError{reason: :closed}}} =
             ShoppingAgent.interpret("get milk and some bread",
               llm:
                 {OpenAI,
                  [
                    api_key: "test",
                    tools: [CaptureIntent],
                    request_options: [adapter: ClosedAdapter, retry: false]
                  ]}
             )
  end

  test "quota errors are unwrapped and are not retried or parsed as successful intents" do
    parent = self()

    plug = fn conn ->
      send(parent, :quota_request)

      conn
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{"error" => %{"code" => "insufficient_quota"}})
    end

    assert {:error, {:openai_http_error, 429, _}} =
             ShoppingAgent.interpret("2 litres of milk",
               llm:
                 {OpenAI,
                  [api_key: "test", tools: [CaptureIntent], request_options: [plug: plug]]}
             )

    assert_receive :quota_request
    refute_receive :quota_request
  end
end
