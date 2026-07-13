defmodule OfficeGraph.ProjectQualityGateTest do
  use ExUnit.Case, async: true

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

  test "verification environment is stable and honors explicit isolation overrides" do
    {first_output, 0} =
      System.cmd("sh", ["bin/verify", "--print-environment"],
        env: [{"OFFICE_GRAPH_POSTGRES_PORT", ""}]
      )

    {second_output, 0} =
      System.cmd("sh", ["bin/verify", "--print-environment"],
        env: [{"OFFICE_GRAPH_POSTGRES_PORT", ""}]
      )

    assert first_output == second_output
    assert first_output =~ ~r/^COMPOSE_PROJECT_NAME=office_graph_[0-9]+$/m
    assert first_output =~ "OFFICE_GRAPH_POSTGRES_PORT=auto"
    assert first_output =~ ~r/^MIX_TEST_PARTITION=_w[0-9]+$/m

    assert compose_published_port("") == "55432"
    assert compose_published_port("0") == "0"
    assert compose_published_port("61234") == "61234"

    assert verify_startup_contract() ==
             {"0",
              [
                "local.hex --force --if-missing",
                "local.rebar --force --if-missing",
                "deps.get",
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

  defp compose_published_port(port) do
    {config, 0} =
      System.cmd("docker", ["compose", "config", "--format", "json"],
        env: [{"OFFICE_GRAPH_POSTGRES_PORT", port}]
      )

    config
    |> Jason.decode!()
    |> get_in(["services", "postgres", "ports", Access.at(0), "published"])
  end

  defp verify_startup_contract do
    fixture_dir =
      Path.join(System.tmp_dir!(), "office_graph_verify_#{System.unique_integer([:positive])}")

    File.mkdir_p!(fixture_dir)
    on_exit(fn -> File.rm_rf!(fixture_dir) end)

    port_log = Path.join(fixture_dir, "postgres-port")
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

    {_output, 0} =
      System.cmd("sh", ["bin/verify"],
        env: [
          {"PATH", fixture_dir <> ":" <> System.fetch_env!("PATH")},
          {"VERIFY_PORT_LOG", port_log},
          {"VERIFY_MIX_LOG", mix_log},
          {"OFFICE_GRAPH_POSTGRES_PORT", ""}
        ],
        stderr_to_stdout: true
      )

    {File.read!(port_log), mix_log |> File.read!() |> String.split("\n", trim: true)}
  end

  defp expand_alias("test", _aliases), do: ["test"]

  defp expand_alias(task, aliases) do
    case aliases[String.to_existing_atom(task)] do
      nil -> [task]
      tasks -> Enum.flat_map(tasks, &expand_alias(&1, aliases))
    end
  rescue
    ArgumentError -> [task]
  end
end
