defmodule OfficeGraph.ProjectQualityGateTest do
  use ExUnit.Case, async: false

  test "canonical aliases execute one complete ExUnit suite" do
    aliases = Mix.Project.config()[:aliases]

    test_tasks =
      aliases[:verify]
      |> Enum.flat_map(&expand_alias(&1, aliases))
      |> Enum.filter(fn task ->
        task == "test" or String.starts_with?(task, "test ")
      end)

    assert test_tasks == ["test"]
    assert aliases[:precommit] == ["verify"]
  end

  test "canonical verification checks unused dependencies without unlocking them" do
    verify = Mix.Project.config()[:aliases][:verify]

    assert "deps.unlock --check-unused" in verify
    assert "dependency.audit" in verify
    refute Enum.any?(verify, &String.starts_with?(&1, "deps.unlock --unused"))
  end

  test "repository-managed database uses the PostgreSQL 18 data layout" do
    config = compose_config("")
    postgres = get_in(config, ["services", "postgres"])
    data_volume = Enum.find(postgres["volumes"], &(&1["target"] == "/var/lib/postgresql"))

    assert postgres["image"] == "postgres:18-alpine"
    assert data_volume
    assert data_volume["source"] == "office_graph_postgres_18_data"
    assert OfficeGraph.Repo.min_pg_version() == Version.parse!("18.0.0")
  end

  test "test query logging is quiet by default and explicitly opt-in" do
    repo_config = Application.fetch_env!(:office_graph, OfficeGraph.Repo)

    assert repo_config[:log] == false

    previous_log_setting = System.get_env("OFFICE_GRAPH_TEST_SQL_LOG")

    on_exit(fn ->
      if previous_log_setting do
        System.put_env("OFFICE_GRAPH_TEST_SQL_LOG", previous_log_setting)
      else
        System.delete_env("OFFICE_GRAPH_TEST_SQL_LOG")
      end
    end)

    System.put_env("OFFICE_GRAPH_TEST_SQL_LOG", "1")

    runtime_config =
      Config.Reader.read!(Path.expand("../../config/runtime.exs", __DIR__), env: :test)

    assert get_in(runtime_config, [:office_graph, OfficeGraph.Repo, :log]) == :debug
  end

  test "canonical verification runs project boundaries exactly once through Credo" do
    aliases = Mix.Project.config()[:aliases]
    expanded_verify = Enum.flat_map(aliases[:verify], &expand_alias(&1, aliases))

    assert Enum.count(expanded_verify, &(&1 == "credo --strict")) == 1
    refute "office_graph.planning_boundaries" in expanded_verify
    refute "office_graph.database_boundaries" in expanded_verify
    refute Keyword.has_key?(aliases, :"office_graph.planning_boundaries")
    refute Keyword.has_key?(aliases, :"office_graph.database_boundaries")
  end

  test "production BEAMs are built before the compiled boundary audit" do
    verify = Mix.Project.config()[:aliases][:verify]
    build_index = Enum.find_index(verify, &(&1 == "production.build"))
    analysis_index = Enum.find_index(verify, &(&1 == "static.analysis"))

    assert is_integer(build_index)
    assert is_integer(analysis_index)
    assert build_index < analysis_index
  end

  test "Nix shell pins the PostgreSQL 18 client used by terminal verification" do
    flake = File.read!("flake.nix")

    assert flake =~ "postgresql = pkgs.postgresql_18"

    assert System.find_executable("pg_dump"),
           "pg_dump is not on PATH; enter the Nix development shell"

    assert {version, 0} = System.cmd("pg_dump", ["--version"])
    assert version =~ ~r/pg_dump \(PostgreSQL\) 18\./
  end

  test "verification environment is stable and honors explicit isolation overrides" do
    {first_output, 0} =
      System.cmd("sh", ["bin/verify", "--print-environment"],
        env: [
          {"COMPOSE_PROJECT_NAME", ""},
          {"MIX_TEST_PARTITION", ""},
          {"OFFICE_GRAPH_POSTGRES_PORT", ""},
          {"OFFICE_GRAPH_SKIP_COMPOSE", ""}
        ]
      )

    {second_output, 0} =
      System.cmd("sh", ["bin/verify", "--print-environment"],
        env: [
          {"COMPOSE_PROJECT_NAME", ""},
          {"MIX_TEST_PARTITION", ""},
          {"OFFICE_GRAPH_POSTGRES_PORT", ""},
          {"OFFICE_GRAPH_SKIP_COMPOSE", ""}
        ]
      )

    assert first_output == second_output
    assert first_output =~ ~r/^COMPOSE_PROJECT_NAME=office_graph_[0-9]+$/m
    assert first_output =~ "OFFICE_GRAPH_POSTGRES_PORT=auto"
    assert first_output =~ ~r/^MIX_TEST_PARTITION=_w[0-9]+$/m

    assert compose_published_port("") == "55432"
    assert compose_published_port("0") == "0"
    assert compose_published_port("61234") == "61234"

    assert verify_startup_contract() ==
             {0, "0", 2,
              [
                "local.hex --force --if-missing",
                "local.rebar --force --if-missing",
                "deps.get --check-locked",
                "ecto.drop --quiet",
                "ecto.create --quiet",
                "ecto.migrate --quiet",
                "run -e OfficeGraph.Release.setup!(); OfficeGraph.Release.setup!()",
                "ecto.rollback --all --quiet",
                "ecto.migrate --quiet",
                "run -e OfficeGraph.Release.setup!(); OfficeGraph.Release.setup!()",
                "run -e OfficeGraph.TestSupport.MigrationConformanceSupport.verify_terminal_database!()",
                "test test/office_graph/release_setup_test.exs",
                "verify"
              ]}

    {overridden_output, 0} =
      System.cmd("sh", ["bin/verify", "--print-environment"],
        env: [
          {"COMPOSE_PROJECT_NAME", "explicit_project"},
          {"OFFICE_GRAPH_POSTGRES_PORT", "61234"},
          {"MIX_TEST_PARTITION", "_explicit"}
        ]
      )

    assert overridden_output =~ "COMPOSE_PROJECT_NAME=explicit_project"
    assert overridden_output =~ "OFFICE_GRAPH_POSTGRES_PORT=61234"
    assert overridden_output =~ "MIX_TEST_PARTITION=_explicit"

    {external_output, 0} =
      System.cmd("sh", ["bin/verify", "--print-environment"],
        env: [
          {"OFFICE_GRAPH_SKIP_COMPOSE", "1"},
          {"OFFICE_GRAPH_POSTGRES_PORT", ""}
        ]
      )

    assert external_output =~ "OFFICE_GRAPH_POSTGRES_PORT=55432"
  end

  test "canonical verification rejects an older Compose PostgreSQL server" do
    assert {1, "0", 2, []} = verify_startup_contract("17.7")
  end

  defp compose_published_port(port) do
    port
    |> compose_config()
    |> get_in(["services", "postgres", "ports", Access.at(0), "published"])
  end

  defp compose_config(port) do
    {config, 0} =
      System.cmd("docker", ["compose", "config", "--format", "json"],
        env: [{"OFFICE_GRAPH_POSTGRES_PORT", port}]
      )

    Jason.decode!(config)
  end

  defp verify_startup_contract(postgres_version \\ "18.4") do
    fixture_dir =
      Path.join(System.tmp_dir!(), "office_graph_verify_#{System.unique_integer([:positive])}")

    File.mkdir_p!(fixture_dir)
    on_exit(fn -> File.rm_rf!(fixture_dir) end)

    port_log = Path.join(fixture_dir, "postgres-port")
    exec_log = Path.join(fixture_dir, "postgres-exec")
    mix_log = Path.join(fixture_dir, "mix-invocations")
    docker = Path.join(fixture_dir, "docker")
    mix = Path.join(fixture_dir, "mix")

    File.write!(docker, """
    #!/usr/bin/env sh
    set -eu

    case "$1 $2" in
      "compose version")
        exit 0
        ;;
      "compose up")
        printf '%s' "${OFFICE_GRAPH_POSTGRES_PORT-unset}" > "$VERIFY_PORT_LOG"
        ;;
      "compose port")
        printf '127.0.0.1:61234\n'
        ;;
      "compose exec")
        printf '%s\n' "$*" >> "$VERIFY_EXEC_LOG"

        case "$*" in
          *"postgres --version")
            printf 'postgres (PostgreSQL) %s\n' "$VERIFY_POSTGRES_VERSION"
            ;;
        esac
        exit 0
        ;;
      *)
        printf 'unexpected docker invocation: %s\n' "$*" >&2
        exit 1
        ;;
    esac
    """)

    File.write!(mix, "#!/usr/bin/env sh\nprintf '%s\\n' \"$*\" >> \"$VERIFY_MIX_LOG\"\n")
    File.chmod!(docker, 0o755)
    File.chmod!(mix, 0o755)

    {output, status} =
      System.cmd("sh", ["bin/verify"],
        env: [
          {"PATH", fixture_dir <> ":" <> System.fetch_env!("PATH")},
          {"VERIFY_EXEC_LOG", exec_log},
          {"VERIFY_PORT_LOG", port_log},
          {"VERIFY_MIX_LOG", mix_log},
          {"VERIFY_POSTGRES_VERSION", postgres_version},
          {"OFFICE_GRAPH_POSTGRES_PORT", ""},
          {"OFFICE_GRAPH_SKIP_COMPOSE", ""}
        ],
        stderr_to_stdout: true
      )

    if postgres_version != "18.4" do
      assert output =~
               "Canonical verification requires PostgreSQL 18; the Compose server reported: postgres (PostgreSQL) #{postgres_version}"
    end

    {
      status,
      File.read!(port_log),
      exec_log |> File.read!() |> String.split("\n", trim: true) |> length(),
      read_lines(mix_log)
    }
  end

  defp read_lines(path) do
    case File.read(path) do
      {:ok, contents} -> String.split(contents, "\n", trim: true)
      {:error, :enoent} -> []
    end
  end

  defp expand_alias("test", _aliases), do: ["test"]
  defp expand_alias(task, _aliases) when is_function(task), do: []

  defp expand_alias(task, aliases) do
    case aliases[String.to_existing_atom(task)] do
      nil -> [task]
      tasks -> Enum.flat_map(tasks, &expand_alias(&1, aliases))
    end
  rescue
    ArgumentError -> [task]
  end
end
