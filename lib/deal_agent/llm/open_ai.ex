defmodule DealAgent.LLM.OpenAI do
  @behaviour BeamAgent.LLM.Client

  @endpoint "https://api.openai.com/v1/responses"

  @impl true
  def chat(messages, opts) do
    # Intent capture is the entire model task. Complete locally after the tool
    # result; the domain handler supplies the shopper's reply.
    case List.last(messages) do
      %{type: :tool_result} ->
        # This completion is local: it makes no provider request.
        {:reply, "Shopping intent captured.", %{input_tokens: 0, output_tokens: 0}}

      _ ->
        request_intent(messages, opts)
    end
  end

  defp request_intent(messages, opts) do
    api_key =
      Keyword.fetch!(opts, :api_key)

    model =
      Keyword.get(
        opts,
        :model,
        "gpt-5.6-luna"
      )

    tools =
      Keyword.get(
        opts,
        :tools,
        []
      )

    body = %{
      model: model,
      instructions: """
      Interpret shopping-list commands using one capture_intent call.
      Supported supermarkets: carrefour, quickmart, naivas, foodplus (Chandarana).
      Put explicitly requested stores in supermarkets, preserving their order.
      Use supermarkets null if no preference was supplied; this keeps the shopper's
      current comparison. "All supermarkets" means all four supported stores.
      Preserve unsupported store names so validation can explain the limitation.
      Store names and comparison instructions must never become shopping items.
      Example: "I want to shop for milk and ice and water. Compare Naivas and Carrefour."
      means add_items with milk, ice, water (quantity/unit null), and supermarkets
      ["naivas", "carrefour"]. "Compare Quickmart" means compare with supermarkets
      ["quickmart"], items null. "Which supermarkets are available?" means
      list_supermarkets with all other fields null. Never invent coverage or stock.
      For multiple requested items use add_items and the items array, with top-level
      name, quantity and unit null. Extract each distinct item independently, preserving
      order, brands and qualifiers. Keep compound names such as "baking soda" together.
      Example: "I want milk, eggs, baking soda kiwi and mangoes" has five items:
      milk; eggs; baking soda; kiwi; mangoes. All have null quantity and unit.
      Preserve explicit amounts on each item, e.g. "2 litres of milk and 6 eggs".
      If there are more than 30 items ask the user to split the list; do not truncate it.
      For a single item use add_item with items null. Other actions also use items null.
      A bare request such as "2 litres of milk" means add_item, with name "milk",
      quantity "2", and unit "litre". Keep quantity and unit out of the name.
      If the user omits quantity, return null for both quantity and unit; never infer an amount.
      Preserve requested brands or product qualifiers in the name. Use null for
      fields that do not apply. Do not invent product prices or store availability.
      """,
      input: encode_messages(messages),
      tools: encode_tools(tools),
      tool_choice: "required",
      parallel_tool_calls: false,
      reasoning: %{
        effort: "low"
      }
    }

    request_options =
      Keyword.merge(
        [
          url: @endpoint,
          json: body,
          headers: [{"authorization", "Bearer #{api_key}"}],
          receive_timeout: 30_000,
          retry: fn
            _request, %Req.TransportError{reason: :closed} -> true
            _request, _response -> false
          end,
          max_retries: 1,
          retry_delay: 300
        ],
        Keyword.get(opts, :request_options, [])
      )

    case Req.post(request_options) do
      {:ok, %{status: 200, body: body}} ->
        with_usage(decode_response(body), body)

      {:ok, response} ->
        {:error, {:openai_http_error, response.status, response.body}}

      {:error, reason} ->
        {:error, {:openai_request_failed, reason}}
    end
  end

  defp with_usage({kind, payload}, %{
         "usage" => %{"input_tokens" => input, "output_tokens" => output}
       })
       when kind in [:reply, :tool_call] and is_integer(input) and input >= 0 and
              is_integer(output) and output >= 0 do
    {kind, payload, %{input_tokens: input, output_tokens: output}}
  end

  defp with_usage(response, _body), do: response

  defp encode_messages(messages) do
    Enum.map(messages, &encode_message/1)
  end

  defp encode_message(%{
         role: :user,
         content: content
       }) do
    %{
      role: "user",
      content: content
    }
  end

  defp encode_message(%{
         role: :system,
         content: content
       }) do
    %{
      role: "system",
      content: content
    }
  end

  defp encode_message(%{
         type: :tool_call,
         call_id: call_id,
         name: name,
         arguments: arguments
       }) do
    %{
      type: "function_call",
      call_id: call_id,
      name: Atom.to_string(name),
      arguments: Jason.encode!(arguments)
    }
  end

  defp encode_message(%{
         type: :tool_result,
         call_id: call_id,
         content: content
       }) do
    %{
      type: "function_call_output",
      call_id: call_id,
      output: encode_tool_output(content)
    }
  end

  defp encode_tool_output(content)
       when is_binary(content),
       do: content

  defp encode_tool_output(content) do
    Jason.encode!(content)
  end

  defp encode_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        name: Atom.to_string(tool.name()),
        description: tool.description(),
        parameters: tool.parameters(),
        strict: true
      }
    end)
  end

  defp decode_response(%{"output" => output}) do
    case Enum.find(
           output,
           &(&1["type"] == "function_call")
         ) do
      nil ->
        decode_text_reply(output)

      function_call ->
        decode_tool_call(function_call)
    end
  end

  defp decode_response(_body), do: {:error, :unexpected_openai_response}

  defp decode_text_reply(output) do
    text =
      output
      |> Enum.filter(&(&1["type"] == "message"))
      |> Enum.flat_map(&Map.get(&1, "content", []))
      |> Enum.filter(&(&1["type"] == "output_text"))
      |> Enum.map_join("", & &1["text"])

    if text == "" do
      {:error, :unexpected_openai_response}
    else
      {:reply, text}
    end
  end

  defp decode_tool_call(%{
         "call_id" => call_id,
         "name" => name,
         "arguments" => encoded_arguments
       }) do
    with {:ok, arguments} <-
           Jason.decode(encoded_arguments) do
      {:tool_call,
       %{
         id: call_id,
         name: String.to_existing_atom(name),
         arguments: arguments
       }}
    end
  end
end
