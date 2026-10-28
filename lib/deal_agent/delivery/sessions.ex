defmodule DealAgent.Delivery.Sessions do
  @moduledoc "Owns temporary location-confirmed store browsers. Cookies stay in the browser process."
  use GenServer
  require Logger
  @stores ~w(carrefour quickmart naivas)
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def start(owner, store, area, coordinates \\ nil) when store in @stores and is_binary(area) do
    with {:ok, point} <- DealAgent.Delivery.Coordinates.normalize(coordinates) do
      ensure_started()
      GenServer.call(__MODULE__, {:start, owner, store, String.trim(area), point})
    end
  end

  def command(owner, id, action) when action in ~w(open close confirm resume locate),
    do: GenServer.call(__MODULE__, {:command, owner, id, action})

  def search(owner, id, store, query),
    do: GenServer.call(__MODULE__, {:search, owner, id, store, query}, :infinity)

  def cart(owner, id, store, plan),
    do: GenServer.call(__MODULE__, {:cart, owner, id, store, plan})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:start, owner, store, area, point}, _, sessions) do
    cond do
      area == "" or String.length(area) > 200 ->
        {:reply, {:error, :invalid_area}, sessions}

      Enum.any?(sessions, fn {_, s} -> s.owner == owner and s.store == store end) ->
        {:reply, {:error, :session_exists}, sessions}

      map_size(sessions) >= 6 ->
        {:reply, {:error, :session_capacity}, sessions}

      true ->
        runtime = Application.get_env(:deal_agent, :delivery_runtime, DealAgent.Delivery.Runtime)

        case runtime.start() do
          {:ok, port} ->
            id = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

            Port.command(
              port,
              Jason.encode!(%{store: store, area: area, coordinates: point}) <> "\n"
            )

            session = %{
              port: port,
              owner: owner,
              store: store,
              ref: Process.monitor(owner),
              confirmed: false,
              automatic: not is_nil(point),
              busy: nil,
              timer: Process.send_after(self(), {:expiry, id}, 1_800_000)
            }

            {:reply, {:ok, id}, Map.put(sessions, id, session)}

          error ->
            {:reply, error, sessions}
        end
    end
  end

  def handle_call({:command, owner, id, action}, _, sessions) do
    case sessions[id] do
      %{owner: ^owner} when action == "close" ->
        {:reply, :ok, close_session(sessions, id)}

      %{owner: ^owner, automatic: true} when action == "confirm" ->
        {:reply, {:error, :automatic_location}, sessions}

      %{owner: ^owner, automatic: true, confirmed: false, busy: nil} = session
      when action == "locate" ->
        Port.command(session.port, Jason.encode!(%{action: action}) <> "\n")
        token = make_ref()
        timer = Process.send_after(self(), {:location_timeout, id, token}, 180_000)
        {:reply, :ok, Map.put(sessions, id, %{session | busy: {:locating, timer, token}})}

      %{owner: ^owner, confirmed: true} when action == "confirm" ->
        {:reply, {:error, :already_confirmed}, sessions}

      %{owner: ^owner} = session
      when action == "open" and
             (is_nil(session.busy) or session.busy == :handoff or session.busy == {:cart, nil}) ->
        Port.command(session.port, Jason.encode!(%{action: action}) <> "\n")
        token = make_ref()
        timer = Process.send_after(self(), {:window_timeout, id, token}, 120_000)

        {:reply, :ok,
         Map.put(sessions, id, %{session | busy: {:window, session.busy, timer, token}})}

      %{owner: ^owner} = session
      when (action == "resume" and session.busy == {:cart, nil}) or
             (action == "confirm" and is_nil(session.busy)) ->
        Port.command(session.port, Jason.encode!(%{action: action}) <> "\n")

        sessions =
          if action == "resume" and session.busy == {:cart, nil},
            do:
              Map.put(sessions, id, %{
                session
                | busy: {:cart, Process.send_after(self(), {:cart_timeout, id}, 240_000)}
              }),
            else: sessions

        {:reply, :ok, sessions}

      _ ->
        {:reply, {:error, :session_unavailable}, sessions}
    end
  end

  def handle_call({:search, owner, id, store, query}, from, sessions) do
    case sessions[id] do
      %{owner: ^owner, store: ^store, confirmed: true, busy: nil} = session ->
        request_id = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

        Port.command(
          session.port,
          Jason.encode!(%{action: "search", id: request_id, query: query}) <> "\n"
        )

        timer = Process.send_after(self(), {:search_timeout, id, request_id}, 50_000)
        monitor = Process.monitor(elem(from, 0))

        {:noreply,
         Map.put(sessions, id, %{session | busy: {:search, request_id, from, timer, monitor}})}

      %{owner: ^owner, store: ^store, confirmed: true} ->
        {:reply, {:error, :session_busy}, sessions}

      _ ->
        {:reply, {:error, :location_unconfirmed}, sessions}
    end
  end

  def handle_call({:cart, _owner, id, _store, plan}, _, sessions)
      when not is_map_key(plan, :delivery_session_id) or plan.delivery_session_id != id do
    {:reply, {:error, :location_unconfirmed}, sessions}
  end

  def handle_call({:cart, owner, id, store, plan}, _, sessions) do
    case sessions[id] do
      %{owner: ^owner, store: ^store, confirmed: true, busy: nil} = session ->
        Port.command(session.port, Jason.encode!(%{action: "cart", plan: plan}) <> "\n")
        timer = Process.send_after(self(), {:cart_timeout, id}, 240_000)
        {:reply, :ok, Map.put(sessions, id, %{session | busy: {:cart, timer}})}

      %{owner: ^owner, store: ^store, confirmed: true} ->
        {:reply, {:error, :session_busy}, sessions}

      _ ->
        {:reply, {:error, :location_unconfirmed}, sessions}
    end
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, sessions) do
    with {id, session} <- Enum.find(sessions, fn {_, s} -> s.port == port end),
         {:ok, event} <- Jason.decode(line) do
      case event do
        %{"type" => "reply", "id" => request_id} ->
          case session.busy do
            {:search, ^request_id, from, timer, monitor} ->
              Process.cancel_timer(timer)
              Process.demonitor(monitor, [:flush])

              result =
                if is_binary(event["html"]),
                  do: {:ok, event["html"]},
                  else: {:error, error(event["error"])}

              GenServer.reply(from, result)
              {:noreply, Map.put(sessions, id, %{session | busy: nil})}

            _ ->
              {:noreply, sessions}
          end

        %{"type" => "window", "status" => status} ->
          send(session.owner, {:delivery_event, id, event})

          case session.busy do
            {:window, previous, timer, _} when status in ["opened", "failed"] ->
              Process.cancel_timer(timer)
              {:noreply, Map.put(sessions, id, %{session | busy: previous})}

            _ ->
              {:noreply, sessions}
          end

        %{"type" => "setup", "status" => "unavailable"} ->
          stage =
            if event["stage"] in ~w(loading_store opening_location loading_map reverse_geocoding autocomplete candidate_geocoding selecting_address saving_location verifying_location retaining_location),
              do: event["stage"],
              else: "unknown"

          code =
            if event["error"] in ~w(map_service_rejected location_timeout location_not_saved address_not_found location_unconfirmed map_timeout location_setup_failed),
              do: event["error"],
              else: "location_setup_failed"

          Logger.warning("supermarket.location.failed",
            supermarket: session.store,
            location_stage: stage,
            error_type: code
          )

          send(session.owner, {:delivery_event, id, event})
          {:noreply, Map.put(sessions, id, %{finish_location(session) | confirmed: false})}

        %{"type" => "confirmed", "location" => location} ->
          send(session.owner, {:delivery_event, id, event})
          session = finish_location(session)
          {:noreply, Map.put(sessions, id, %{session | confirmed: is_map(location)})}

        %{"type" => "invalidated"} ->
          send(session.owner, {:delivery_event, id, event})
          {:noreply, close_session(sessions, id)}

        %{"type" => "cart", "status" => status} ->
          send(session.owner, {:cart_event, id, event})

          if status in ["ready", "needs_attention", "failed"] do
            if match?({:cart, _}, session.busy),
              do: if(elem(session.busy, 1), do: Process.cancel_timer(elem(session.busy, 1)))

            # Leave this session reserved for payment review. No new searches can
            # navigate the user's checkout window or replay an existing basket.
            {:noreply, Map.put(sessions, id, %{session | busy: :handoff})}
          else
            if status == "awaiting_input" and match?({:cart, _}, session.busy) do
              if elem(session.busy, 1), do: Process.cancel_timer(elem(session.busy, 1))

              {:noreply, Map.put(sessions, id, %{session | busy: {:cart, nil}})}
            else
              {:noreply, sessions}
            end
          end

        %{"type" => "closed"} ->
          {:noreply, close_session(sessions, id)}

        _ ->
          send(session.owner, {:delivery_event, id, event})
          {:noreply, sessions}
      end
    else
      _ -> {:noreply, sessions}
    end
  end

  def handle_info({:search_timeout, id, request_id}, sessions) do
    case sessions[id] do
      %{busy: {:search, ^request_id, _, _, _}} -> {:noreply, close_session(sessions, id)}
      _ -> {:noreply, sessions}
    end
  end

  def handle_info({:location_timeout, id, token}, sessions) do
    case sessions[id] do
      %{busy: {:locating, _, ^token}} -> {:noreply, close_session(sessions, id)}
      _ -> {:noreply, sessions}
    end
  end

  def handle_info({:window_timeout, id, token}, sessions) do
    case sessions[id] do
      %{busy: {:window, _, _, ^token}} -> {:noreply, close_session(sessions, id)}
      _ -> {:noreply, sessions}
    end
  end

  def handle_info({:cart_timeout, id}, sessions) do
    case sessions[id] do
      %{busy: {:cart, timer}} when not is_nil(timer) -> {:noreply, close_session(sessions, id)}
      _ -> {:noreply, sessions}
    end
  end

  def handle_info({:expiry, id}, sessions), do: {:noreply, close_session(sessions, id)}

  def handle_info({port, {:exit_status, _}}, sessions) do
    case Enum.find(sessions, fn {_, s} -> s.port == port end) do
      {id, _} -> {:noreply, close_session(sessions, id)}
      _ -> {:noreply, sessions}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, sessions) do
    ids = for {id, s} <- sessions, s.ref == ref, do: id
    {:noreply, Enum.reduce(ids, sessions, &close_session(&2, &1))}
  end

  def handle_info(_, sessions), do: {:noreply, sessions}

  @impl true
  def terminate(_, sessions),
    do: Enum.each(sessions, fn {_, s} -> if Port.info(s.port), do: Port.close(s.port) end)

  defp finish_location(%{busy: {:locating, timer, _}} = session) do
    Process.cancel_timer(timer)
    %{session | busy: nil}
  end

  defp finish_location(session), do: session

  defp close_session(sessions, id) do
    case Map.pop(sessions, id) do
      {nil, sessions} ->
        sessions

      {s, sessions} ->
        if Port.info(s.port), do: Port.close(s.port)
        Process.cancel_timer(s.timer)
        Process.demonitor(s.ref, [:flush])

        case s.busy do
          {:search, _, from, timer, monitor} ->
            Process.cancel_timer(timer)
            Process.demonitor(monitor, [:flush])
            GenServer.reply(from, {:error, :location_unconfirmed})

          {:locating, timer, _} ->
            Process.cancel_timer(timer)

          {:window, _, timer, _} ->
            Process.cancel_timer(timer)

          {:cart, timer} ->
            if timer, do: Process.cancel_timer(timer)

          _ ->
            :ok
        end

        send(s.owner, {:delivery_event, id, %{"type" => "closed"}})

        send(
          s.owner,
          {:cart_event, id,
           %{
             "status" => "closed",
             "message" =>
               "The store location session was closed. Confirm the location again before searching."
           }}
        )

        sessions
    end
  end

  defp error("location_changed"), do: :location_changed
  defp error("session_busy"), do: :session_busy
  defp error(_), do: :location_unconfirmed

  defp ensure_started do
    if Process.whereis(__MODULE__) == nil do
      case Supervisor.start_child(DealAgent.Supervisor, {__MODULE__, []}) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end
  end
end
