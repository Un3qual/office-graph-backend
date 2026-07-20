defmodule OfficeGraph.Application do
  use Boundary, top_level?: true, deps: [OfficeGraph, OfficeGraph.Repo, OfficeGraphWeb]

  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    maybe_install_ecto_dev_logger()

    children =
      [
        OfficeGraphWeb.Telemetry,
        OfficeGraph.Repo,
        {DNSCluster, query: Application.get_env(:office_graph, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: OfficeGraph.PubSub},
        OfficeGraph.AgentRuntime.AdapterState,
        OfficeGraph.GitHubIntegration.Adapter.GitHub.TokenCache
      ] ++
        OfficeGraph.DurableDelivery.subscription_children() ++
        [
          {Oban, Application.fetch_env!(:office_graph, Oban)},
          OfficeGraphWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: OfficeGraph.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OfficeGraphWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  if Code.ensure_loaded?(Ecto.DevLogger) do
    defp maybe_install_ecto_dev_logger, do: Ecto.DevLogger.install(OfficeGraph.Repo)
  else
    defp maybe_install_ecto_dev_logger, do: :ok
  end
end
