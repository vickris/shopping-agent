defmodule DealAgent.Logging.JSONFormatter do
  @moduledoc "JSON console output with an explicit operational metadata allowlist."

  @fields [
    :request_id,
    :beam_agent_event,
    :run_key,
    :outcome,
    :execution_status,
    :verification_status,
    :error_type,
    :kind,
    :duration,
    :iterations,
    :tool_calls,
    :iteration,
    :before_count,
    :after_count,
    :compressed_messages,
    :summary_chars,
    :configured_max_messages,
    :minimum_messages,
    :guardrail,
    :phase,
    :unit,
    :observed,
    :limit
  ]
  @message_format Logger.Formatter.compile("$message")

  def format(level, message, {{year, month, day}, {hour, minute, second, millisecond}}, metadata) do
    timestamp =
      NaiveDateTime.new!(year, month, day, hour, minute, second, {millisecond * 1000, 3})
      |> NaiveDateTime.to_iso8601()
      |> Kernel.<>("Z")

    fields =
      metadata
      |> Keyword.take(@fields)
      |> Enum.filter(fn {_, value} ->
        is_binary(value) or is_atom(value) or is_integer(value) or is_float(value)
      end)
      |> Map.new()
      |> add_duration()

    record =
      Map.merge(fields, %{
        timestamp: timestamp,
        level: level,
        message:
          Logger.Formatter.format(@message_format, level, message, nil, [])
          |> IO.iodata_to_binary()
      })

    [Jason.encode!(record), "\n"]
  rescue
    _ -> "{\"level\":\"error\",\"message\":\"log_format_failed\"}\n"
  end

  defp add_duration(%{duration: duration} = fields) when is_integer(duration) and duration >= 0 do
    fields
    |> Map.put(:duration_unit, "native")
    |> Map.put(:duration_ms, System.convert_time_unit(duration, :native, :microsecond) / 1000)
  end

  defp add_duration(fields), do: fields
end
