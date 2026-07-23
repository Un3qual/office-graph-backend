defmodule OfficeGraph.AgentRuntime.RuntimeReadinessTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.AgentRuntime.RuntimeReadiness

  defmodule ReadyRunner do
    def run(git, ["-C", root, "rev-parse", "HEAD"], opts) do
      send(Application.fetch_env!(:office_graph, :runtime_readiness_test_pid), {
        :git_revision_readiness,
        git,
        root,
        opts
      })

      {:ok, String.duplicate("a", 40) <> "\n"}
    end

    def run(git, ["-C", root, "rev-parse", "--absolute-git-dir"], opts) do
      send(Application.fetch_env!(:office_graph, :runtime_readiness_test_pid), {
        :git_directory_readiness,
        git,
        root,
        opts
      })

      {:ok, Path.join(root, ".git") <> "\n"}
    end

    def run(git, ["-C", root, "status", "--porcelain=v1", "--untracked-files=all"], opts) do
      send(Application.fetch_env!(:office_graph, :runtime_readiness_test_pid), {
        :git_worktree_readiness,
        git,
        root,
        opts
      })

      {:ok, ""}
    end

    def run(git, ["-C", root, "show", "HEAD:openspec/project.md"], opts) do
      send(Application.fetch_env!(:office_graph, :runtime_readiness_test_pid), {
        :git_project_readiness,
        git,
        root,
        opts
      })

      {:ok, "# Project\n"}
    end

    def run(openspec, ["list", "--json"], opts) do
      send(Application.fetch_env!(:office_graph, :runtime_readiness_test_pid), {
        :openspec_readiness,
        openspec,
        opts
      })

      {:ok, ~s({"changes": []})}
    end
  end

  defmodule FailingRunner do
    def run(_executable, _argv, _opts), do: {:error, :command_failed}
  end

  defmodule StageFailureRunner do
    def run(executable, argv, opts) do
      case {Application.fetch_env!(:office_graph, :runtime_readiness_failure_stage), argv} do
        {:revision, ["-C", _root, "rev-parse", "HEAD"]} ->
          {:ok, "not-a-revision\n"}

        {:git_directory, ["-C", _root, "rev-parse", "--absolute-git-dir"]} ->
          {:ok, "/outside/runtime/repository.git\n"}

        {:working_tree, ["-C", _root, "status", "--porcelain=v1", "--untracked-files=all"]} ->
          {:ok, " M openspec/project.md\n"}

        {:project, ["-C", _root, "show", "HEAD:openspec/project.md"]} ->
          {:error, :command_failed}

        {:openspec_command, ["list", "--json"]} ->
          {:error, :command_failed}

        {:openspec_json, ["list", "--json"]} ->
          {:ok, "not-json"}

        _other ->
          ReadyRunner.run(executable, argv, opts)
      end
    end
  end

  setup do
    Application.put_env(:office_graph, :runtime_readiness_test_pid, self())

    root =
      Path.join(System.tmp_dir!(), "office-graph-runtime-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    on_exit(fn ->
      Application.delete_env(:office_graph, :runtime_readiness_test_pid)
      Application.delete_env(:office_graph, :runtime_readiness_failure_stage)
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "validates the mounted repository and configured tool executables", %{root: root} do
    config = runtime_config(root)

    assert :ok = RuntimeReadiness.check(config, ReadyRunner)

    assert_receive {:git_revision_readiness, "/runtime/bin/git", ^root,
                    [timeout_ms: 5_000, max_bytes: 128]}

    assert_receive {:git_directory_readiness, "/runtime/bin/git", ^root,
                    [timeout_ms: 5_000, max_bytes: 4_096]}

    assert_receive {:git_worktree_readiness, "/runtime/bin/git", ^root,
                    [timeout_ms: 5_000, max_bytes: 65_536]}

    assert_receive {:git_project_readiness, "/runtime/bin/git", ^root,
                    [timeout_ms: 5_000, max_bytes: 65_536]}

    assert_receive {:openspec_readiness, "/runtime/bin/openspec",
                    [
                      cd: ^root,
                      environment: %{"OPENSPEC_TELEMETRY" => "0"},
                      timeout_ms: 5_000,
                      max_bytes: 65_536
                    ]}
  end

  test "rejects relative or missing repository mounts before starting workers", %{root: root} do
    assert {:error, :agent_runtime_repository_root_not_absolute} =
             RuntimeReadiness.check(
               %{runtime_config(root) | repository_root: "relative/repo"},
               ReadyRunner
             )

    missing = Path.join(root, "missing")

    assert {:error, :agent_runtime_repository_unavailable} =
             RuntimeReadiness.check(
               %{runtime_config(root) | repository_root: missing},
               ReadyRunner
             )
  end

  test "rejects unavailable git or OpenSpec tooling before starting workers", %{root: root} do
    assert {:error, :agent_runtime_git_unavailable} =
             RuntimeReadiness.check(runtime_config(root), FailingRunner)

    assert_raise RuntimeError, ~r/agent_runtime_git_unavailable/, fn ->
      RuntimeReadiness.check!(runtime_config(root), FailingRunner)
    end
  end

  test "rejects invalid revisions, missing project artifacts, and unusable OpenSpec inventory", %{
    root: root
  } do
    for {stage, expected} <- [
          {:revision, :agent_runtime_repository_unavailable},
          {:git_directory, :agent_runtime_repository_unavailable},
          {:working_tree, :agent_runtime_repository_unavailable},
          {:project, :agent_runtime_repository_unavailable},
          {:openspec_command, :agent_runtime_openspec_unavailable},
          {:openspec_json, :agent_runtime_openspec_unavailable}
        ] do
      Application.put_env(:office_graph, :runtime_readiness_failure_stage, stage)

      assert {:error, ^expected} =
               RuntimeReadiness.check(runtime_config(root), StageFailureRunner)
    end
  end

  test "requires absolute configured executable paths", %{root: root} do
    assert {:error, :agent_runtime_git_not_absolute} =
             RuntimeReadiness.check(%{runtime_config(root) | git_executable: "git"}, ReadyRunner)

    assert {:error, :agent_runtime_openspec_not_absolute} =
             RuntimeReadiness.check(
               %{runtime_config(root) | openspec_executable: "openspec"},
               ReadyRunner
             )
  end

  defp runtime_config(root) do
    %{
      repository_root: root,
      git_executable: "/runtime/bin/git",
      openspec_executable: "/runtime/bin/openspec"
    }
  end
end
