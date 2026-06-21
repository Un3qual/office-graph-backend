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
    OfficeGraph.Audit.Domain,
    OfficeGraph.Revisions.Domain,
    OfficeGraph.Tombstones.Domain,
    OfficeGraph.Content.Domain,
    OfficeGraph.WorkGraph.Domain
  ],
  ecto_repos: [OfficeGraph.Repo],
  generators: [timestamp_type: :utc_datetime]

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
