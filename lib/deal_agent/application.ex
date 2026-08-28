defmodule DealAgent.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DealAgentWeb.Telemetry,
      DealAgent.Repo,
      {DNSCluster, query: Application.get_env(:deal_agent, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DealAgent.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: DealAgent.Finch},
      # Start a worker by calling: DealAgent.Worker.start_link(arg)
      # {DealAgent.Worker, arg},
      # Start to serve requests, typically the last entry
      DealAgentWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DealAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DealAgentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
