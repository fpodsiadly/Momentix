defmodule Momentix.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MomentixWeb.Telemetry,
      Momentix.Repo,
      {DNSCluster, query: Application.get_env(:momentix, :dns_cluster_query) || :ignore},
      {Finch, name: Momentix.Finch},
      Momentix.Cache,
      {Phoenix.PubSub, name: Momentix.PubSub},
      {Registry, keys: :unique, name: Momentix.MatchRegistry},
      Momentix.MatchSupervisor,
      # Start to serve requests, typically the last entry
      MomentixWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Momentix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MomentixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
