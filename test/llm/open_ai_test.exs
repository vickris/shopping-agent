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

  test "tool results finish locally without issuing a second model request" do
    assert {:reply, "Shopping intent captured."} =
             OpenAI.chat(
               [%{role: :tool, type: :tool_result, call_id: "call_1", content: "captured"}],
               []
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
