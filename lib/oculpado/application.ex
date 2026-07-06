defmodule Oculpado.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Carrega as partidas em memória (persistent_term) antes de tudo.
    Oculpado.Data.load()

    children = [
      OculpadoWeb.Telemetry,
      Oculpado.Repo,
      {DNSCluster, query: Application.get_env(:oculpado, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Oculpado.PubSub},
      # Contagem de votos em memória (ETS), com persistência em SQLite
      Oculpado.Votes,
      # Start to serve requests, typically the last entry
      OculpadoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Oculpado.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OculpadoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
