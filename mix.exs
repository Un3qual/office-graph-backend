defmodule OfficeGraph.MixProject do
  use Mix.Project

  def project do
    [
      app: :office_graph,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_add_deps: :app_tree,
        plt_add_apps: [:ex_unit],
        flags: [:error_handling, :underspecs]
      ],
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {OfficeGraph.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        verify: :test,
        "architecture.conformance": :test,
        "frontend.verify.precompiled": :test,
        "spec.verify": :test,
        "static.analysis": :test,
        typecheck: :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:ash, "~> 3.29"},
      {:simple_sat, "~> 0.1"},
      {:ash_postgres, "~> 2.10"},
      {:ash_graphql, "~> 1.9"},
      {:ash_json_api, "~> 1.6"},
      {:absinthe, "~> 1.11"},
      {:absinthe_relay, "~> 1.6"},
      {:absinthe_plug, "~> 1.5"},
      {:oban, "~> 2.20"},
      {:boundary, "~> 0.10.4", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:ecto_dev_logger, "~> 0.15.0", only: :dev}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "architecture.conformance": [
        "test test/office_graph/architecture/ash_conformance_test.exs"
      ],
      "assets.setup": ["cmd --cd assets pnpm install --frozen-lockfile"],
      "assets.build": [
        "assets.setup",
        "cmd --cd assets pnpm run router:deploy",
        "cmd --cd assets pnpm run verify:app-shell"
      ],
      "assets.deploy": ["assets.build", "phx.digest"],
      "frontend.verify": ["assets.setup", "cmd --cd assets pnpm run verify"],
      "frontend.verify.precompiled": [
        "assets.setup",
        "cmd --cd assets env OFFICE_GRAPH_SCHEMA_PRECOMPILED=1 pnpm run verify"
      ],
      "spec.verify": [
        "cmd openspec validate --specs --strict",
        "cmd openspec validate --changes --strict"
      ],
      "static.analysis": [
        "credo --strict",
        "ex_dna #{Enum.join(ex_dna_paths(), " ")} --min-mass 45 --literal-mode abstract --normalize-pipes --min-similarity 0.9 --exclude-macro schema --exclude-macro pipe_through --exclude-macro plug --exclude-macro field --exclude-macro object --exclude-macro input_object --exclude-macro policies --exclude-macro policy --exclude-macro authorize_if --max-clones 0",
        "reach.check --arch --smells --strict"
      ],
      typecheck: ["dialyzer --quiet-with-result"],
      release: ["assets.deploy", "release"],
      "boundary.check": ["compile --force --warnings-as-errors"],
      verify: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "boundary.check",
        "static.analysis",
        "typecheck",
        "architecture.conformance",
        "hex.audit",
        "frontend.verify.precompiled",
        "spec.verify",
        "test"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "boundary.check",
        "static.analysis",
        "typecheck",
        "architecture.conformance",
        "hex.audit",
        "frontend.verify.precompiled",
        "spec.verify",
        "test"
      ]
    ]
  end

  defp ex_dna_paths do
    [
      "lib/office_graph/*.ex",
      "lib/office_graph/runs/changes/*.ex",
      "lib/office_graph/work_graph/changes/*.ex",
      "lib/office_graph/work_graph/proposal_commands.ex",
      "lib/office_graph/work_graph/command_support.ex",
      "lib/office_graph/work_graph/queries.ex",
      "lib/office_graph/work_graph/verification_commands.ex",
      "lib/office_graph/work_packets/changes/*.ex",
      "lib/office_graph/work_packets/readiness.ex"
    ]
  end
end
