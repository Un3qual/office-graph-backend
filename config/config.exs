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
    OfficeGraph.ProposedChanges.Domain,
    OfficeGraph.WorkGraph.Domain,
    OfficeGraph.WorkPackets.Domain,
    OfficeGraph.Runs.Domain
  ],
  allow_local_api_owner_bootstrap: false,
  ecto_repos: [OfficeGraph.Repo],
  generators: [timestamp_type: :utc_datetime]

config :office_graph, Oban,
  repo: OfficeGraph.Repo,
  queues: [delivery: 10, integrations: 5, agents: 5],
  plugins: [{Oban.Plugins.Pruner, max_age: 30 * 24 * 60 * 60}]

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
