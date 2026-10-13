defmodule DealAgent.Checkout.CartJobs do
  @moduledoc "Supervises cart preparation and retains the browser session for the local checkout handoff."
  use GenServer
  @terminal ["ready", "needs_attention", "failed", "closed"]
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def start(owner, plan) do
    ensure_started()
    GenServer.call(__MODULE__, {:start, owner, plan})
  end

  def command(owner, id, action) when action in ["open", "close"],
    do: GenServer.call(__MODULE__, {:command, owner, id, action})

  def init(state), do: {:ok, state}

  def handle_call({:start, owner, plan}, _, jobs) do
    cond do
      Enum.any?(jobs, fn {_, job} -> job.owner == owner end) ->
        {:reply, {:error, :cart_already_open}, jobs}

      map_size(jobs) >= 3 ->
        {:reply, {:error, :cart_capacity}, jobs}

      true ->
        runtime = Application.get_env(:deal_agent, :cart_runtime, DealAgent.Checkout.CartRuntime)

        case runtime.start() do
          {:ok, port} ->
            id = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
            Port.command(port, Jason.encode!(plan) <> "\n")
            timeout = Process.send_after(self(), {:timeout, id}, 240_000)
            expiry = Process.send_after(self(), {:expiry, id}, 1_800_000)

            job = %{
              port: port,
              owner: owner,
              status: "preparing",
              timeout: timeout,
              expiry: expiry
            }

            {:reply, {:ok, id}, Map.put(jobs, id, job)}

          {:error, reason} ->
            {:reply, {:error, reason}, jobs}
        end
    end
  end

  def handle_call({:command, owner, id, action}, _, jobs) do
    case jobs[id] do
      %{owner: ^owner, port: port} ->
        result =
          try do
            Port.command(port, Jason.encode!(%{action: action}) <> "\n")
            :ok
          rescue
            ArgumentError -> {:error, :unknown_cart}
          end

        {:reply, result, jobs}

      _ ->
        {:reply, {:error, :unknown_cart}, jobs}
    end
  end

  def handle_info({port, {:data, {:eol, line}}}, jobs) do
    with {id, job} <- Enum.find(jobs, fn {_, job} -> job.port == port end),
         {:ok, %{"status" => status} = event} <- Jason.decode(line),
         true <- status in ["preparing" | @terminal] do
      # A terminal result cannot be overwritten by delayed preparation messages.
      if job.status not in @terminal or status == "closed" do
        send(job.owner, {:cart_event, id, event})
        if status in @terminal, do: Process.cancel_timer(job.timeout)
        {:noreply, Map.put(jobs, id, %{job | status: status})}
      else
        {:noreply, jobs}
      end
    else
      _ -> {:noreply, jobs}
    end
  end

  def handle_info({port, {:exit_status, _}}, jobs) do
    case Enum.find(jobs, fn {_, job} -> job.port == port end) do
      {id, job} ->
        status = if job.status == "preparing", do: "failed", else: "closed"

        send(
          job.owner,
          {:cart_event, id,
           %{
             "status" => status,
             "message" =>
               if(status == "failed",
                 do: "The cart browser stopped before verification.",
                 else: "The Carrefour cart window was closed."
               )
           }}
        )

        Process.cancel_timer(job.timeout)
        Process.cancel_timer(job.expiry)
        {:noreply, Map.delete(jobs, id)}

      _ ->
        {:noreply, jobs}
    end
  end

  def handle_info({kind, id}, jobs) when kind in [:timeout, :expiry] do
    case jobs[id] do
      nil ->
        {:noreply, jobs}

      %{status: status} when kind == :timeout and status != "preparing" ->
        {:noreply, jobs}

      job ->
        status = if kind == :timeout, do: "failed", else: "closed"

        send(
          job.owner,
          {:cart_event, id,
           %{
             "status" => status,
             "message" =>
               if(kind == :timeout,
                 do: "Cart preparation timed out. Please retry after reviewing your selections.",
                 else: "The cart browser session expired after 30 minutes."
               )
           }}
        )

        Port.close(job.port)
        Process.cancel_timer(job.timeout)
        Process.cancel_timer(job.expiry)
        {:noreply, Map.delete(jobs, id)}
    end
  end

  def handle_info(_, jobs), do: {:noreply, jobs}

  def terminate(_, jobs),
    do: Enum.each(jobs, fn {_, job} -> if Port.info(job.port), do: Port.close(job.port) end)

  defp ensure_started do
    if Process.whereis(__MODULE__) == nil do
      case Supervisor.start_child(DealAgent.Supervisor, {__MODULE__, []}) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        {:error, :already_present} -> Supervisor.restart_child(DealAgent.Supervisor, __MODULE__)
      end
    end
  end
end
