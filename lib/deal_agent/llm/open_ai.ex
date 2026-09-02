defmodule DealAgent.LLM.OpenAI do
  @behaviour BeamAgent.LLM.Behaviour

  @endpoint "https://api.openai.com/v1/responses"

  @impl true
  def chat(messages, opts) do
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
      input: encode_messages(messages),
      tools: encode_tools(tools),
      tool_choice: "required",
      reasoning: %{
        effort: "low"
      }
    }

    case Req.post(
           @endpoint,
           json: body,
           headers: [
             {"authorization", "Bearer #{api_key}"}
           ]
         ) do
      {:ok, %{status: 200, body: body}} ->
        decode_response(body)

      {:ok, response} ->
        {:error, {:openai_http_error, response.status, response.body}}

      {:error, reason} ->
        {:error, {:openai_request_failed, reason}}
    end
  end

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
