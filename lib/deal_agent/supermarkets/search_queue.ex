defmodule DealAgent.Supermarkets.SearchQueue do
  @moduledoc "FIFO execution per supermarket, with caller cancellation and bounded worker lifetime."
  use GenServer

  @names %{
    carrefour: DealAgent.CarrefourQueue,
    quickmart: DealAgent.QuickmartQueue,
    naivas: DealAgent.NaivasQueue
  }

  def child_spec(store),
    do: %{id: Map.fetch!(@names, store), start: {__MODULE__, :start_link, [store]}}

  def start_link(store), do: GenServer.start_link(__MODULE__, [], name: Map.fetch!(@names, store))

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

    GenServer.call(name, {:run, work}, :infinity)
  end

  def init(_), do: {:ok, %{pending: :queue.new(), active: nil}}

  def handle_call({:run, work}, {caller, _} = from, state) do
    job = %{from: from, work: work, caller_ref: Process.monitor(caller)}
    {:noreply, dispatch(%{state | pending: :queue.in(job, state.pending)})}
  end

  def handle_info({:finished, token, result}, %{active: %{token: token} = job} = state) do
    GenServer.reply(job.from, result)
    cleanup(job)
    {:noreply, dispatch(%{state | active: nil})}
  end

  def handle_info({:expired, token}, %{active: %{token: token} = job} = state) do
    Process.exit(job.pid, :kill)
    GenServer.reply(job.from, {:error, :browser_timeout})
    cleanup(job)
    {:noreply, dispatch(%{state | active: nil})}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{active: job} = state)
      when not is_nil(job) and (ref == job.caller_ref or ref == job.worker_ref) do
    Process.exit(job.pid, :kill)
    if ref == job.worker_ref, do: GenServer.reply(job.from, {:error, :browser_search_failed})
    cleanup(job)
    {:noreply, dispatch(%{state | active: nil})}
  end

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    pending =
      state.pending
      |> :queue.to_list()
      |> Enum.reject(&(&1.caller_ref == ref))
      |> :queue.from_list()

    {:noreply, %{state | pending: pending}}
  end

  def handle_info(_, state), do: {:noreply, state}

  def terminate(_, %{active: job}) do
    if job, do: Process.exit(job.pid, :kill)
  end

  defp dispatch(%{active: nil} = state) do
    case :queue.out(state.pending) do
      {:empty, _} ->
        state

      {{:value, job}, pending} ->
        parent = self()
        token = make_ref()
        {pid, worker_ref} = spawn_monitor(fn -> send(parent, {:finished, token, job.work.()}) end)
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
