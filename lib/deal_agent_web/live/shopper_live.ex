defmodule DealAgentWeb.ShopperLive do
  use DealAgentWeb, :live_view

  alias DealAgent.Checkout.{CartPlan, CartJobs}
  alias DealAgent.Delivery.Sessions, as: DeliverySessions
  alias DealAgent.Agents.ShoppingAgent
  alias DealAgent.Chat.Message
  alias DealAgent.Shopping.IntentHandler
  alias DealAgent.Shopping.Selection
  alias DealAgent.Shopping.Item
  alias DealAgent.Shopping.ShoppingList
  alias DealAgent.Supermarkets.{Carrefour, Quickmart, Naivas}

  @stores [
    %{
      id: "carrefour",
      label: "Carrefour",
      adapter: Carrefour,
      results_key: :carrefour_results,
      selections_key: :carrefour_selections,
      options_key: :carrefour_search_options
    },
    %{
      id: "quickmart",
      label: "Quickmart",
      adapter: Quickmart,
      results_key: :quickmart_results,
      selections_key: :quickmart_selections,
      options_key: :quickmart_search_options
    },
    %{
      id: "naivas",
      label: "Naivas",
      adapter: Naivas,
      results_key: :naivas_results,
      selections_key: :naivas_selections,
      options_key: :naivas_search_options
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:shopping_list, ShoppingList.new())
     |> assign(:cart_jobs, %{})
     |> assign(:candidate_filters, %{})
     |> assign(:store_queries, %{})
     |> assign(:delivery_sessions, %{})
     |> assign(:units, Item.units())
     |> assign(:messages, [])
     |> assign(:agent_status, :idle)
     |> assign(:naivas_selections, %{})
     |> assign(:naivas_results, %{})
     |> assign(:quickmart_selections, %{})
     |> assign(:quickmart_results, %{})
     |> assign(:stores, @stores)
     |> assign(:carrefour_selections, %{})
     |> assign(:carrefour_results, %{})
     |> assign_item_form()
     |> assign_chat_form()}
  end

  def handle_event("setup-delivery", %{"store" => store_id, "area" => area} = params, socket) do
    with store when not is_nil(store) <- store_for(params),
         true <- is_binary(area) and String.trim(area) != "" and String.length(area) <= 200,
         false <- not is_nil(socket.assigns.delivery_sessions[store_id]),
         {:ok, id} <- DeliverySessions.start(self(), store_id, area) do
      socket = invalidate_store(socket, store)

      profile = %{
        id: id,
        status: "opening",
        area: String.trim(area),
        label: nil,
        message: "Opening the store’s delivery selector…"
      }

      {:noreply,
       assign(
         socket,
         :delivery_sessions,
         Map.put(socket.assigns.delivery_sessions, store_id, profile)
       )}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Close the existing store session, then enter a delivery area of 1–200 characters."
         )}
    end
  end

  def handle_event("delivery-window", %{"store" => store_id, "action" => action}, socket)
      when action in ["open", "close", "confirm"] do
    case socket.assigns.delivery_sessions[store_id] do
      %{id: id} ->
        case DeliverySessions.command(self(), id, action) do
          :ok when action == "confirm" ->
            profile = socket.assigns.delivery_sessions[store_id]

            updated = %{
              profile
              | status: "confirming",
                message: "Checking the store’s saved delivery location…"
            }

            {:noreply,
             assign(
               socket,
               :delivery_sessions,
               Map.put(socket.assigns.delivery_sessions, store_id, updated)
             )}

          :ok ->
            {:noreply, socket}

          _ ->
            {:noreply, put_flash(socket, :error, "This store session is busy or closed.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("shop-now", %{"store" => store_id} = params, socket) do
    case store_for(params) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unknown supermarket.")}

      store ->
        current = socket.assigns.cart_jobs[store_id]

        if current && current.status != "closed" do
          {:noreply,
           put_flash(
             socket,
             :error,
             "Close the existing #{store.label} cart window before preparing another basket."
           )}
        else
          with {:ok, plan} <-
                 CartPlan.build(
                   socket.assigns.shopping_list.items,
                   socket.assigns[store.selections_key],
                   store.adapter.name()
                 ),
               {:ok, id} <- start_cart(socket, store, plan) do
            job = %{
              id: id,
              status: "preparing",
              message:
                "Opening #{store.label} for #{plan.selected_count} selected item(s); skipping #{plan.skipped_count} unselected item(s)…",
              estimated_total: plan.estimated_total
            }

            {:noreply,
             assign(socket, :cart_jobs, Map.put(socket.assigns.cart_jobs, store_id, job))}
          else
            {:error, reason} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 String.replace(cart_error_message(reason), "Carrefour", store.label)
               )}
          end
        end
    end
  end

  def handle_event("cart-window", %{"action" => action} = params, socket)
      when action in ["open", "close", "resume"] do
    store_id = Map.get(params, "store", "carrefour")

    case socket.assigns.cart_jobs[store_id] do
      %{id: id} ->
        case cart_command(socket, store_id, id, action) do
          :ok ->
            socket =
              if action == "resume",
                do:
                  assign(
                    socket,
                    :cart_jobs,
                    Map.update!(
                      socket.assigns.cart_jobs,
                      store_id,
                      &%{&1 | status: "preparing", message: "Continuing cart preparation."}
                    )
                  ),
                else: socket

            {:noreply, socket}

          _ ->
            {:noreply, put_flash(socket, :error, "This cart window is no longer available.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "filter-products",
        %{"store" => store_id, "item_id" => item_id, "query" => query},
        socket
      ) do
    if store_for(%{"store" => store_id}) &&
         Enum.any?(socket.assigns.shopping_list.items, &(&1.id == item_id)) do
      {:noreply,
       assign(
         socket,
         :candidate_filters,
         Map.put(
           socket.assigns.candidate_filters,
           {store_id, item_id},
           String.slice(query, 0, 200)
         )
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "search-products",
        %{"store" => _store_id, "item_id" => item_id, "query" => query} = params,
        socket
      )
      when is_binary(query) do
    item = Enum.find(socket.assigns.shopping_list.items, &(&1.id == item_id))
    store = store_for(params)
    query = String.trim(query)

    cond do
      is_nil(item) or is_nil(store) ->
        {:noreply, socket}

      Map.get(socket.assigns[store.results_key], item_id) == :loading ->
        {:noreply, socket}

      query == "" or String.length(query) > 200 ->
        {:noreply, put_flash(socket, :error, "Enter a supermarket search of 1–200 characters.")}

      true ->
        {:noreply, search_store(socket, item, store, query)}
    end
  end

  @impl true
  def handle_event(
        "select-product",
        %{"item-id" => item_id, "product-id" => product_id} = params,
        socket
      ) do
    item = Enum.find(socket.assigns.shopping_list.items, &(&1.id == item_id))

    with store when not is_nil(store) <- store_for(params),
         %Item{} <- item,
         {:ok, result} <- Map.get(socket.assigns[store.results_key], item_id),
         product when not is_nil(product) <- Enum.find(result.products, &(&1.id == product_id)),
         {:ok, selection} <- Selection.new(item, product) do
      {:noreply,
       assign(
         socket,
         store.selections_key,
         Map.put(
           socket.assigns[store.selections_key],
           item_id,
           selection
           |> Map.put(:search_query, result.query)
           |> Map.put(
             :delivery_session_id,
             get_in(socket.assigns.delivery_sessions, [store.id, :id])
           )
         )
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear-selection", %{"id" => item_id} = params, socket) do
    case store_for(params) do
      nil ->
        {:noreply, socket}

      store ->
        {:noreply,
         assign(
           socket,
           store.selections_key,
           Map.delete(socket.assigns[store.selections_key], item_id)
         )}
    end
  end

  def handle_event("update-packs", %{"item_id" => item_id, "packs" => value} = params, socket) do
    with store when not is_nil(store) <- store_for(params),
         selection when not is_nil(selection) <- socket.assigns[store.selections_key][item_id],
         {packs, ""} when packs > 0 <- Integer.parse(value) do
      {:noreply,
       assign(
         socket,
         store.selections_key,
         Map.put(
           socket.assigns[store.selections_key],
           item_id,
           Selection.resize(selection, packs)
         )
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("retry-search", %{"id" => item_id} = params, socket) do
    item = Enum.find(socket.assigns.shopping_list.items, &(&1.id == item_id))
    store = store_for(params)

    if item && store && Map.get(socket.assigns[store.results_key], item_id) != :loading do
      {:noreply, search_store(socket, item, store)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "add-item",
        %{
          "shopping_item" => %{
            "item_name" => name,
            "quantity" => quantity,
            "unit" => unit
          }
        },
        socket
      ) do
    with name when name != "" <- String.trim(name),
         {:ok, quantity} <- parse_quantity(quantity),
         {:ok, unit} <- parse_unit(unit) do
      item =
        Item.new(name,
          quantity: quantity,
          unit: unit
        )

      shopping_list =
        ShoppingList.add_item(
          socket.assigns.shopping_list,
          item
        )

      {:noreply,
       socket
       |> assign(:shopping_list, shopping_list)
       |> assign_item_form(%{
         "item_name" => "",
         "quantity" => "1",
         "unit" => "each"
       })
       |> search_item(item)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid shopping item")}
    end
  end

  @impl true
  def handle_event(
        "update-item-name",
        %{"new_name" => new_name},
        socket
      ) do
    {:noreply, assign(socket, :item_name, new_name)}
  end

  @impl true
  def handle_event(
        "remove-item",
        %{"id" => item_id},
        socket
      ) do
    shopping_list =
      ShoppingList.remove_item(
        socket.assigns.shopping_list,
        item_id
      )

    {:noreply,
     socket
     |> assign(:shopping_list, shopping_list)
     |> prune_search_results()}
  end

  @impl true
  def handle_event(
        "send-message",
        %{"chat" => %{"message" => content}},
        socket
      ) do
    content = String.trim(content)

    cond do
      content == "" ->
        {:noreply, socket}

      command = chat_command(content) ->
        {:noreply, run_chat_command(socket, content, command)}

      socket.assigns.agent_status == :thinking ->
        {:noreply, socket}

      true ->
        user_message =
          Message.new(:user, content)

        messages =
          socket.assigns.messages ++
            [user_message]

        socket =
          socket
          |> assign(
            :messages,
            messages
          )
          |> assign(:agent_status, :thinking)
          |> assign_chat_form()

        {:noreply,
         start_async(
           socket,
           {:interpret_message, user_message.id},
           fn ->
             ShoppingAgent.interpret(content)
           end
         )}
    end
  end

  @impl true
  def handle_async(
        {:interpret_message, _message_id},
        {:ok, {:ok, intent}},
        socket
      ) do
    {:noreply, apply_shopping_intent(socket, intent)}
  end

  def handle_async({:search_store, store_id, item_id, session_id}, {:ok, result}, socket) do
    if get_in(socket.assigns.delivery_sessions, [store_id, :id]) == session_id and
         get_in(socket.assigns.delivery_sessions, [store_id, :status]) == "confirmed" do
      {:noreply, put_search_result(socket, store_id, item_id, result)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:search_store, store_id, item_id, session_id}, {:exit, _}, socket) do
    if get_in(socket.assigns.delivery_sessions, [store_id, :id]) == session_id do
      {:noreply, put_search_result(socket, store_id, item_id, {:error, :location_unconfirmed})}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:search_store, store_id, item_id}, {:ok, result}, socket) do
    {:noreply, put_search_result(socket, store_id, item_id, result)}
  end

  def handle_async({:search_store, store_id, item_id}, {:exit, _reason}, socket) do
    {:noreply, put_search_result(socket, store_id, item_id, {:error, :search_failed})}
  end

  def handle_async(
        {:interpret_message, _message_id},
        {:ok, {:error, reason}},
        socket
      ) do
    {:noreply,
     socket
     |> append_assistant_message(agent_error_message(reason))
     |> assign(:agent_status, :idle)}
  end

  def handle_async(
        {:interpret_message, _message_id},
        {:exit, reason},
        socket
      ) do
    require Logger

    Logger.error("Shopping agent async task failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> append_assistant_message("Something went wrong while processing your request.")
     |> assign(:agent_status, :idle)}
  end

  defp store_for(params),
    do: Enum.find(@stores, &(&1.id == Map.get(params, "store", "carrefour")))

  defp agent_error_message(:missing_openai_api_key) do
    "The shopper assistant is not configured yet. Please set OPENAI_API_KEY and restart the server."
  end

  defp agent_error_message({:openai_request_failed, %Req.TransportError{reason: reason}}) do
    "The OpenAI connection failed (#{reason}). Your request has not been added. Please try again or use the Add form above."
  end

  defp agent_error_message({:openai_http_error, status, body}) do
    code = if is_map(body), do: get_in(body, ["error", "code"]), else: nil

    cond do
      status in [401, 403] ->
        "OpenAI rejected the API credentials (HTTP #{status}). Check the server's API key and project permissions."

      status == 429 and
          code in [
            "insufficient_quota",
            "credit_balance_exhausted",
            "organization_usage_limit_exceeded"
          ] ->
        "OpenAI API credits or the account usage limit have been exhausted. Check API billing and limits."

      status == 429 ->
        "OpenAI is rate limiting requests. Please try again shortly."

      status == 404 or code == "model_not_found" ->
        "The configured OpenAI model is unavailable to this API project. Check the model configuration."

      status >= 500 ->
        "OpenAI is temporarily unavailable (HTTP #{status}). Please try again later."

      true ->
        "OpenAI rejected the interpretation request (HTTP #{status}). Check the server's OpenAI request configuration."
    end
  end

  defp agent_error_message(:unexpected_openai_response),
    do: "OpenAI returned an unexpected response. Please try again or use the Add form above."

  defp agent_error_message(_reason) do
    "I couldn't understand that shopping request. Please try rephrasing it."
  end

  defp append_assistant_message(socket, content) do
    assistant_message =
      Message.new(:assistant, content)

    messages =
      socket.assigns.messages ++
        [assistant_message]

    assign(socket, :messages, messages)
  end

  defp apply_shopping_intent(
         socket,
         intent
       ) do
    case IntentHandler.handle(
           intent,
           socket.assigns.shopping_list
         ) do
      {:ok, shopping_list, reply} ->
        socket =
          socket
          |> assign(:shopping_list, shopping_list)
          |> append_assistant_message(reply)
          |> assign(:agent_status, :idle)
          |> prune_search_results()

        case intent.action do
          :add_item -> search_item(socket, intent.item)
          :add_items -> Enum.reduce(intent.items, socket, &search_item(&2, &1))
          _ -> socket
        end

      {:compare, shopping_list, reply} ->
        socket
        |> assign(:shopping_list, shopping_list)
        |> append_assistant_message(reply)
        |> assign(:agent_status, :idle)
        |> search_all_items()

      {:error, shopping_list, reply} ->
        socket
        |> assign(:shopping_list, shopping_list)
        |> append_assistant_message(reply)
        |> assign(:agent_status, :idle)
    end
  end

  @impl true
  def handle_info({:delivery_event, id, event}, socket) do
    case Enum.find(socket.assigns.delivery_sessions, fn {_, profile} -> profile.id == id end) do
      {store_id, profile} ->
        store = store_for(%{"store" => store_id})

        case event do
          %{"type" => "confirmed", "location" => location} ->
            socket = invalidate_store(socket, store)

            updated =
              %{
                profile
                | status: "confirmed",
                  label: location["label"],
                  message:
                    if(location["confirmation"] == "user_override",
                      do:
                        "Using your supplied area. Naivas has not verified delivery there; check the address and availability at checkout.",
                      else: "Using the delivery location you confirmed in the store window."
                    )
              }
              |> Map.put(:confirmation, location["confirmation"])
              |> Map.put(:branch_id, location["branch_id"])
              |> Map.put(:branch, location["branch"])

            socket =
              assign(
                clear_flash(socket, :error),
                :delivery_sessions,
                Map.put(socket.assigns.delivery_sessions, store_id, updated)
              )

            {:noreply,
             Enum.reduce(socket.assigns.shopping_list.items, socket, &search_store(&2, &1, store))}

          %{"type" => type} when type in ["closed", "invalidated"] ->
            socket = invalidate_store(socket, store)

            profiles =
              if type == "closed",
                do: Map.delete(socket.assigns.delivery_sessions, store_id),
                else:
                  Map.put(socket.assigns.delivery_sessions, store_id, %{
                    profile
                    | status: "awaiting_input",
                      message:
                        "Delivery location changed. Check the store window and confirm again."
                  })

            {:noreply, assign(socket, :delivery_sessions, profiles)}

          %{"type" => "setup_error", "message" => message} ->
            {:noreply, put_flash(socket, :error, message)}

          %{"type" => "confirmation_failed", "message" => message} ->
            updated = %{profile | status: "awaiting_input", message: message}

            {:noreply,
             socket
             |> assign(
               :delivery_sessions,
               Map.put(socket.assigns.delivery_sessions, store_id, updated)
             )
             |> put_flash(:error, message)}

          %{"message" => message} ->
            updated = %{profile | status: "awaiting_input", message: message}

            {:noreply,
             assign(
               socket,
               :delivery_sessions,
               Map.put(socket.assigns.delivery_sessions, store_id, updated)
             )}

          _ ->
            {:noreply, socket}
        end

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:cart_event, id, event}, socket) do
    case Enum.find(socket.assigns.cart_jobs, fn {_, job} -> job.id == id end) do
      {store_id, job} ->
        status = event["status"]

        if status in ["ready", "needs_attention"] and event["verified"] != true do
          handle_info(
            {:cart_event, id,
             %{"status" => "failed", "message" => "The cart could not be verified."}},
            socket
          )
        else
          updated = %{job | status: status, message: event["message"]}

          socket =
            assign(socket, :cart_jobs, Map.put(socket.assigns.cart_jobs, store_id, updated))

          socket =
            if status in ["ready", "needs_attention", "awaiting_input", "failed"],
              do:
                push_event(socket, "cart-notification", %{
                  type: if(status in ["ready", "needs_attention"], do: "success", else: "error"),
                  message: event["message"]
                }),
              else: socket

          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp cart_error_message(:session_busy),
    do:
      "Wait for this store’s searches to finish, or close its existing cart before preparing another."

  defp cart_error_message(:location_unconfirmed),
    do: "Confirm this store’s delivery location and search again before shopping."

  defp cart_error_message(:incomplete_basket),
    do: "Select a product for every Carrefour row before shopping."

  defp cart_error_message(:empty_basket),
    do: "Select at least one Carrefour product before shopping."

  defp cart_error_message(:invalid_selection),
    do: "A selected Carrefour product is invalid or unavailable. Search again and reselect it."

  defp cart_error_message(:pack_limit),
    do: "Cart preparation supports up to 50 packs per product."

  defp cart_error_message(:cart_already_open), do: "A Carrefour cart window is already open."

  defp cart_error_message(:cart_capacity),
    do: "All cart browsers are busy. Close an existing cart window and try again."

  defp cart_error_message(_),
    do:
      "The Carrefour cart browser could not start. Check that Node and Playwright Firefox are installed."

  defp filtered_products(products, query) do
    terms = query |> String.downcase() |> String.split()

    Enum.filter(products, fn product ->
      name = String.downcase(product.name)
      Enum.all?(terms, &String.contains?(name, &1))
    end)
  end

  defp request_amount(%{quantity_unspecified: true}),
    do: "Quantity unspecified · 1 pack on selection"

  defp request_amount(item),
    do: Decimal.to_string(item.quantity, :normal) <> format_unit(item.unit)

  defp search_item(socket, item) do
    Enum.reduce(@stores, socket, &search_store(&2, item, &1))
  end

  defp search_store(socket, item, store, query \\ nil) do
    query = query || Map.get(socket.assigns.store_queries, {store.id, item.id}, item.name)
    search_item = %{item | name: query}
    options = Application.get_env(:deal_agent, store.options_key, [])
    profile = socket.assigns.delivery_sessions[store.id]

    socket =
      socket
      |> assign(:store_queries, Map.put(socket.assigns.store_queries, {store.id, item.id}, query))
      |> assign(
        :candidate_filters,
        Map.delete(socket.assigns.candidate_filters, {store.id, item.id})
      )
      |> assign(store.selections_key, Map.delete(socket.assigns[store.selections_key], item.id))

    if (is_nil(profile) or profile.status != "confirmed") and
         Application.get_env(:deal_agent, :require_delivery_location, true) do
      assign(
        socket,
        store.results_key,
        Map.put(socket.assigns[store.results_key], item.id, {:error, :location_unconfirmed})
      )
    else
      options =
        if profile && profile.status == "confirmed",
          do:
            options
            |> Keyword.put(:client, Module.concat(store.adapter, BrowserClient))
            |> Keyword.put(:delivery_session, {self(), profile.id}),
          else: options

      task =
        if profile,
          do: {:search_store, store.id, item.id, profile.id},
          else: {:search_store, store.id, item.id}

      socket
      |> assign(store.results_key, Map.put(socket.assigns[store.results_key], item.id, :loading))
      |> start_async(task, fn ->
        case store.adapter.search(search_item, options) do
          {:ok, result} ->
            metadata =
              if profile,
                do:
                  Map.merge(result.metadata || %{}, %{
                    delivery_session_id: profile.id,
                    delivery_area: profile.area,
                    delivery_label: profile.label,
                    branch_id: Map.get(profile, :branch_id),
                    branch: Map.get(profile, :branch),
                    delivery_confirmation:
                      if(Map.get(profile, :confirmation) == "user_override",
                        do: :user_override,
                        else: :user_confirmed
                      )
                  }),
                else: result.metadata

            {:ok, %{result | requested_item: item, metadata: metadata}}

          other ->
            other
        end
      end)
    end
  end

  defp invalidate_store(socket, store) do
    socket =
      Enum.reduce(socket.assigns.shopping_list.items, socket, fn item, acc ->
        acc = cancel_async(acc, {:search_store, store.id, item.id})

        case socket.assigns.delivery_sessions[store.id] do
          %{id: id} -> cancel_async(acc, {:search_store, store.id, item.id, id})
          _ -> acc
        end
      end)

    socket |> assign(store.results_key, %{}) |> assign(store.selections_key, %{})
  end

  defp start_cart(socket, store, plan) do
    case socket.assigns.delivery_sessions[store.id] do
      %{id: id, status: "confirmed"} ->
        selected =
          for item <- socket.assigns.shopping_list.items,
              selection = socket.assigns[store.selections_key][item.id],
              do: selection

        if Enum.all?(selected, &(Map.get(&1, :delivery_session_id) == id)) do
          case DeliverySessions.cart(
                 self(),
                 id,
                 store.id,
                 Map.put(plan, :delivery_session_id, id)
               ) do
            :ok -> {:ok, id}
            error -> error
          end
        else
          {:error, :location_unconfirmed}
        end

      _ ->
        if Application.get_env(:deal_agent, :require_delivery_location, true),
          do: {:error, :location_unconfirmed},
          else: CartJobs.start(self(), plan)
    end
  end

  defp cart_command(socket, store_id, id, action) do
    if get_in(socket.assigns.delivery_sessions, [store_id, :id]) == id,
      do: DeliverySessions.command(self(), id, action),
      else: CartJobs.command(self(), id, action)
  end

  defp search_all_items(socket) do
    Enum.reduce(socket.assigns.shopping_list.items, socket, fn item, acc ->
      search_item(acc, item)
    end)
  end

  defp put_search_result(socket, store_id, item_id, result) do
    store = store_for(%{"store" => store_id})

    if store && Enum.any?(socket.assigns.shopping_list.items, &(&1.id == item_id)) do
      assign(
        socket,
        store.results_key,
        Map.put(socket.assigns[store.results_key], item_id, result)
      )
    else
      socket
    end
  end

  defp prune_search_results(socket) do
    item_ids = Enum.map(socket.assigns.shopping_list.items, & &1.id)

    socket =
      assign(
        socket,
        :candidate_filters,
        Map.filter(socket.assigns.candidate_filters, fn {{_, id}, _} -> id in item_ids end)
      )

    socket =
      assign(
        socket,
        :store_queries,
        Map.filter(socket.assigns.store_queries, fn {{_, id}, _} -> id in item_ids end)
      )

    Enum.reduce(@stores, socket, fn store, acc ->
      removed_ids = Map.keys(acc.assigns[store.results_key]) -- item_ids

      acc =
        Enum.reduce(removed_ids, acc, fn id, current ->
          current = cancel_async(current, {:search_store, store.id, id})

          case socket.assigns.delivery_sessions[store.id] do
            %{id: session_id} -> cancel_async(current, {:search_store, store.id, id, session_id})
            _ -> current
          end
        end)

      acc
      |> assign(store.results_key, Map.take(acc.assigns[store.results_key], item_ids))
      |> assign(store.selections_key, Map.take(acc.assigns[store.selections_key], item_ids))
    end)
  end

  defp search_error_message(reason, _) when reason in [:location_unconfirmed, :location_changed],
    do:
      "Confirm this store’s delivery location above before searching. Default-area results are not used."

  defp search_error_message(:session_busy, _),
    do: "This store window is busy with another search or cart. Try again after it finishes."

  defp search_error_message({:quickmart_http_error, 429}, store),
    do: "#{store.label} is receiving too many requests. Please try again later."

  defp search_error_message(reason, store),
    do: String.replace(search_error_message(reason), "Carrefour", store.label)

  defp store_search_url(%{id: "naivas"}, query), do: Naivas.Client.search_url(query)
  defp store_search_url(%{id: "quickmart"}, query), do: Quickmart.Client.search_url(query)
  defp store_search_url(_, query), do: Carrefour.Client.search_url(query)

  defp search_error_message(:unexpected_search_response),
    do: "Carrefour did not return a readable search page. Please try again later."

  defp search_error_message({:carrefour_http_error, 429}),
    do: "Carrefour is receiving too many requests. Please try again later."

  defp search_error_message(reason)
       when reason in [:browser_dependency_missing, :browser_not_installed],
       do:
         "Automatic Carrefour search needs its browser runtime installed. You can view products on Carrefour below."

  defp search_error_message(:browser_http2_error),
    do:
      "The headless browser could not load Carrefour: its HTTP/2 connection failed. Please try again later or view the store below."

  defp search_error_message(:browser_busy),
    do: "Another Carrefour search is running. Please search again in a moment."

  defp search_error_message(:browser_timeout),
    do:
      "Carrefour took too long to return products. Please try again or open its search page below."

  defp search_error_message(_reason),
    do: "We couldn't search Carrefour right now. Please try again later."

  defp format_product_size(%{quantity: nil}), do: "Pack size unknown"
  defp format_product_size(%{unit: nil}), do: "Pack size unknown"

  defp format_product_size(product) do
    Decimal.to_string(product.quantity, :normal) <> format_unit(product.unit)
  end

  defp selectable?(item, product), do: match?({:ok, _}, Selection.new(item, product))

  defp format_price(price), do: "KES " <> Decimal.to_string(Decimal.round(price, 2), :normal)

  defp parse_quantity(value) do
    case Decimal.parse(value) do
      {quantity, ""} ->
        if Decimal.compare(quantity, 0) == :gt do
          {:ok, quantity}
        else
          {:error, :invalid_quantity}
        end

      _ ->
        {:error, :invalid_quantity}
    end
  end

  defp parse_unit(unit) do
    case unit do
      "each" -> {:ok, :each}
      "gram" -> {:ok, :gram}
      "kilogram" -> {:ok, :kilogram}
      "millilitre" -> {:ok, :millilitre}
      "litre" -> {:ok, :litre}
      _ -> {:error, :invalid_unit}
    end
  end

  defp format_unit(:each), do: " each"
  defp format_unit(:gram), do: " g"
  defp format_unit(:kilogram), do: " kg"
  defp format_unit(:millilitre), do: " ml"
  defp format_unit(:litre), do: " L"

  defp assign_item_form(socket, params \\ nil) do
    params =
      params ||
        %{
          "item_name" => "",
          "quantity" => "1",
          "unit" => "each"
        }

    assign(
      socket,
      :item_form,
      to_form(params, as: :shopping_item)
    )
  end

  defp assign_chat_form(socket, params \\ %{"message" => ""}) do
    assign(
      socket,
      :chat_form,
      to_form(params, as: :chat)
    )
  end

  # Commands handled locally, without a round-trip through the agent/LLM.
  defp chat_command(content) do
    case String.downcase(content) do
      "clear list" -> :clear_list
      _ -> nil
    end
  end

  defp run_chat_command(socket, content, :clear_list) do
    user_message = Message.new(:user, content)

    socket
    |> assign(:messages, socket.assigns.messages ++ [user_message])
    |> assign(:shopping_list, ShoppingList.new())
    |> prune_search_results()
    |> assign(:naivas_selections, %{})
    |> assign(:naivas_results, %{})
    |> assign(:quickmart_selections, %{})
    |> assign(:quickmart_results, %{})
    |> assign(:stores, @stores)
    |> assign(:carrefour_selections, %{})
    |> assign(:carrefour_results, %{})
    |> append_assistant_message("Your shopping list has been cleared.")
    |> assign(:agent_status, :idle)
    |> assign_chat_form()
  end
end
