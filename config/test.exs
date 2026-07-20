import Config

config :office_graph, allow_local_api_owner_bootstrap: true
config :office_graph, :github_secret_store, OfficeGraph.GitHubIntegration.SecretStore.TestAdapter
config :office_graph, :github_adapter, OfficeGraph.GitHubIntegration.Adapter.TestAdapter

config :office_graph, :agent_runtime_adapters,
  models: %{"deterministic" => OfficeGraph.AgentRuntime.Adapters.DeterministicModel},
  tools: %{"deterministic-tool" => OfficeGraph.AgentRuntime.Adapters.DeterministicTool}

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :office_graph, OfficeGraph.Repo,
  username: System.get_env("OFFICE_GRAPH_TEST_DATABASE_USERNAME", "office_graph"),
  password: System.get_env("OFFICE_GRAPH_TEST_DATABASE_PASSWORD", "office_graph"),
  hostname: System.get_env("OFFICE_GRAPH_TEST_DATABASE_HOST", "localhost"),
  port:
    String.to_integer(
      System.get_env("OFFICE_GRAPH_TEST_DATABASE_PORT") ||
        System.get_env("OFFICE_GRAPH_POSTGRES_PORT", "55432")
    ),
  database:
    System.get_env("OFFICE_GRAPH_TEST_DATABASE_NAME", "office_graph_test") <>
      System.get_env("MIX_TEST_PARTITION", ""),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :office_graph, Oban,
  testing: :manual,
  queues: false,
  plugins: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :office_graph, OfficeGraphWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "pM86mIBn3Bgbc4DH0ixmGqZz1YqN/1PYnNFbh5+hurSMBaA94okFGYiIOvLJhoMW",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
