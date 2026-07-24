# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :office_graph,
  ash_domains: [
    OfficeGraph.Tenancy.Domain,
    OfficeGraph.Identity.Domain,
    OfficeGraph.Authorization.Domain,
    OfficeGraph.Operations.Domain,
    OfficeGraph.DurableDelivery.Domain,
    OfficeGraph.Audit.Domain,
    OfficeGraph.Revisions.Domain,
    OfficeGraph.Tombstones.Domain,
    OfficeGraph.Content.Domain,
    OfficeGraph.Integrations.Domain,
    OfficeGraph.ExternalRefs.Domain,
    OfficeGraph.SoftwareProving.Domain,
    OfficeGraph.GitHubIntegration.Domain,
    OfficeGraph.ProposedChanges.Domain,
    OfficeGraph.WorkGraph.Domain,
    OfficeGraph.WorkPackets.Domain,
    OfficeGraph.Runs.Domain,
    OfficeGraph.AgentRuntime.Domain,
    OfficeGraph.NodeConversations.Domain
  ],
  allow_local_api_owner_bootstrap: false,
  ecto_repos: [OfficeGraph.Repo],
  generators: [timestamp_type: :utc_datetime]

config :office_graph,
       :github_secret_store,
       OfficeGraph.GitHubIntegration.SecretStore.Environment

config :office_graph,
       :github_adapter,
       OfficeGraph.GitHubIntegration.Adapter.GitHub

config :office_graph,
       :github_http_client,
       OfficeGraph.GitHubIntegration.Adapter.GitHub.HTTPClient.Httpc

config :office_graph, :github_api_url, "https://api.github.com"

config :office_graph, :agent_runtime_adapters,
  models: %{"deterministic" => OfficeGraph.AgentRuntime.Adapters.DeterministicModel},
  tools: %{"deterministic-tool" => OfficeGraph.AgentRuntime.Adapters.DeterministicTool}

config :office_graph, :agent_runtime_retention_limit, 32

config :office_graph,
       :github_record_loader,
       OfficeGraph.GitHubIntegration.RecordLoader.AshAdapter

config :office_graph, Oban,
  repo: OfficeGraph.Repo,
  queues: [delivery: 10, integrations: 5, agents: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 30 * 24 * 60 * 60},
    {Oban.Plugins.Lifeline, rescue_after: 5 * 60 * 1_000}
  ]

# Configure the endpoint
config :office_graph, OfficeGraphWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: OfficeGraphWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: OfficeGraph.PubSub

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
