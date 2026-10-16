defmodule DealAgent.Supermarkets.SearchLogging do
  @moduledoc "Operational search logs; queries, products and raw failure reasons never enter records."
  require Logger

  @errors [
    :browser_http2_error,
    :browser_dependency_missing,
    :browser_not_installed,
    :browser_timeout,
    :browser_http_error,
    :browser_search_failed,
    :unexpected_search_response,
    :invalid_query
  ]

  def event(name, job, extra \\ []) do
    event = "supermarket.search." <> name

    metadata =
      [
        search_event: event,
        search_id: job.search_id,
        supermarket: job.store,
        request_id: job.request_id,
        queue_wait_ms: wait_ms(job)
      ] ++ extra

    Logger.info(event, metadata)
  end

  def completed(job, {:ok, products}) when is_list(products),
    do: event("stop", job, timing(job) ++ [outcome: :ok, product_count: length(products)])

  def completed(job, {:error, {:browser_http_error, status}}) when status in 100..599,
    do:
      event(
        "stop",
        job,
        timing(job) ++ [outcome: :error, error_type: :browser_http_error, http_status: status]
      )

  def completed(job, {:error, reason}),
    do: stopped(job, :error, if(reason in @errors, do: reason, else: :search_failed))

  def completed(job, _), do: event("stop", job, timing(job) ++ [outcome: :ok])

  def stopped(job, outcome, error),
    do: event("stop", job, timing(job) ++ [outcome: outcome, error_type: error])

  defp timing(%{started_at: started}),
    do: [phase: :active, duration: max(System.monotonic_time() - started, 0)]

  defp timing(_), do: [phase: :queued]

  defp wait_ms(job) do
    stop = Map.get(job, :started_at, System.monotonic_time())
    System.convert_time_unit(max(stop - job.enqueued_at, 0), :native, :microsecond) / 1000
  end
end
