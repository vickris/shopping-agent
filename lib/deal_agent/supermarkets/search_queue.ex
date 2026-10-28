defmodule DealAgent.Supermarkets.SearchQueue do
  @moduledoc "FIFO execution per supermarket, with caller cancellation and bounded worker lifetime."
  use GenServer
  alias DealAgent.Supermarkets.SearchLogging

  @names %{
    carrefour: DealAgent.CarrefourQueue,
    quickmart: DealAgent.QuickmartQueue,
    naivas: DealAgent.NaivasQueue,
    foodplus: DealAgent.FoodplusQueue
  }

  def child_spec(store),
    do: %{id: Map.fetch!(@names, store), start: {__MODULE__, :start_link, [store]}}

  def start_link(store),
    do: GenServer.start_link(__MODULE__, store, name: Map.fetch!(@names, store))

  def run(store, work) do
    name = Map.fetch!(@names, store)
    # Also attach queues to a development server already running before this module was added.
    if Process.whereis(name) == nil do
      case Supervisor.start_child(DealAgent.Supervisor, child_spec(store)) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        {:error, :already_present} -> Supervisor.restart_child(DealAgent.Supervisor, name)
      end
    end

    GenServer.call(name, {:run, work, Logger.metadata()[:request_id]}, :infinity)
  end

  @impl true
  def init(store), do: {:ok, %{store: store, pending: :queue.new(), active: nil}}

  @impl true
  def code_change(_old_version, state, _extra), do: {:ok, upgrade_state(state)}

  # Phoenix reloads callback code without rerunning init/1. Existing queue
  # processes (and work already queued in them) retain the previous state shape.
  @impl true
  def handle_call(message, from, state) when not is_map_key(state, :store),
    do: handle_call(message, from, upgrade_state(state))

  def handle_call({:run, work}, from, state),
    do: handle_call({:run, work, nil}, from, state)

  def handle_call({:run, work, request_id}, {caller, _} = from, state) do
    job = %{
      from: from,
      work: work,
      caller_ref: Process.monitor(caller),
      store: state.store,
      search_id: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false),
      request_id: if(is_binary(request_id), do: request_id, else: nil),
      enqueued_at: System.monotonic_time()
    }

    SearchLogging.event("queued", job, queue_depth: :queue.len(state.pending) + 1)
    {:noreply, dispatch(%{state | pending: :queue.in(job, state.pending)})}
  end

  @impl true
  def handle_info(message, state) when not is_map_key(state, :store),
    do: handle_info(message, upgrade_state(state))

  def handle_info({:finished, token, result}, %{active: %{token: token} = job} = state) do
    SearchLogging.completed(job, result)
    GenServer.reply(job.from, result)
    cleanup(job)
    {:noreply, dispatch(%{state | active: nil})}
  end

  def handle_info({:expired, token}, %{active: %{token: token} = job} = state) do
    SearchLogging.stopped(job, :error, :browser_timeout)
    Process.exit(job.pid, :kill)
    GenServer.reply(job.from, {:error, :browser_timeout})
    cleanup(job)
    {:noreply, dispatch(%{state | active: nil})}
  end

  def handle_info({:worker_failed, token}, %{active: %{token: token} = job} = state) do
    SearchLogging.stopped(job, :error, :worker_exit)
    GenServer.reply(job.from, {:error, :browser_search_failed})
    cleanup(job)
    {:noreply, dispatch(%{state | active: nil})}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{active: job} = state)
      when not is_nil(job) and (ref == job.caller_ref or ref == job.worker_ref) do
    SearchLogging.stopped(
      job,
      if(ref == job.caller_ref, do: :cancelled, else: :error),
      if(ref == job.caller_ref, do: :caller_cancelled, else: :worker_exit)
    )

    Process.exit(job.pid, :kill)
    if ref == job.worker_ref, do: GenServer.reply(job.from, {:error, :browser_search_failed})
    cleanup(job)
    {:noreply, dispatch(%{state | active: nil})}
  end

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    Enum.each(:queue.to_list(state.pending), fn job ->
      if job.caller_ref == ref, do: SearchLogging.stopped(job, :cancelled, :caller_cancelled)
    end)

    pending =
      state.pending
      |> :queue.to_list()
      |> Enum.reject(&(&1.caller_ref == ref))
      |> :queue.from_list()

    {:noreply, %{state | pending: pending}}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, state) do
    state = upgrade_state(state)

    Enum.each(
      :queue.to_list(state.pending),
      &SearchLogging.stopped(&1, :cancelled, :queue_shutdown)
    )

    if state.active do
      SearchLogging.stopped(state.active, :cancelled, :queue_shutdown)
      Process.exit(state.active.pid, :kill)
    end
  end

  defp upgrade_state(%{store: _} = state), do: state

  defp upgrade_state(state) do
    {:registered_name, name} = Process.info(self(), :registered_name)

    store =
      Enum.find_value(@names, fn {store, registered} -> if registered == name, do: store end)

    now = System.monotonic_time()

    upgrade_job = fn job ->
      Map.merge(
        %{
          store: store,
          search_id: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false),
          request_id: nil,
          enqueued_at: now
        },
        job
      )
    end

    active = if state.active, do: state.active |> upgrade_job.() |> Map.put_new(:started_at, now)
    pending = state.pending |> :queue.to_list() |> Enum.map(upgrade_job) |> :queue.from_list()
    Map.merge(state, %{store: store, active: active, pending: pending})
  end

  defp dispatch(%{active: nil} = state) do
    case :queue.out(state.pending) do
      {:empty, _} ->
        state

      {{:value, job}, pending} ->
        parent = self()
        token = make_ref()
        job = Map.put(job, :started_at, System.monotonic_time())
        SearchLogging.event("start", job, queue_depth: :queue.len(pending))

        {pid, worker_ref} =
          spawn_monitor(fn ->
            try do
              send(parent, {:finished, token, job.work.()})
            catch
              _, _ -> send(parent, {:worker_failed, token})
            end
          end)

        timer = Process.send_after(self(), {:expired, token}, 60_000)

        %{
          state
          | pending: pending,
            active:
              Map.merge(job, %{pid: pid, worker_ref: worker_ref, timer: timer, token: token})
        }
    end
  end

  defp dispatch(state), do: state

  defp cleanup(job) do
    Process.cancel_timer(job.timer)
    Process.demonitor(job.caller_ref, [:flush])
    Process.demonitor(job.worker_ref, [:flush])
  end
end
