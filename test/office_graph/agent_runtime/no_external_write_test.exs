defmodule OfficeGraph.AgentRuntime.NoExternalWriteTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.AgentRuntime.{AdapterRegistry, ToolInput}
  alias OfficeGraph.AgentRuntime.Agents.OpenSpecReview
  alias OfficeGraph.AgentRuntime.Tools.{OpenSpecRead, RepositoryRead}

  defmodule CapturingCommandRunner do
    def run(executable, argv, opts) do
      send(Application.fetch_env!(:office_graph, :agent_runtime_command_runner_test_pid), {
        :command_run,
        executable,
        argv,
        opts
      })

      {:ok, ~s({"changes":[]})}
    end
  end

  setup do
    original_runner = Application.get_env(:office_graph, :agent_runtime_command_runner)
    Application.put_env(:office_graph, :agent_runtime_command_runner_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:office_graph, :agent_runtime_command_runner_test_pid)

      if original_runner do
        Application.put_env(:office_graph, :agent_runtime_command_runner, original_runner)
      else
        Application.delete_env(:office_graph, :agent_runtime_command_runner)
      end
    end)

    :ok
  end

  test "the canonical review agent exposes only registered read-only tools" do
    manifest = OpenSpecReview.manifest()

    assert manifest.definition_key == "openspec-review"
    assert manifest.external_write == false
    assert manifest.tool_keys == ["repository.read", "openspec.read"]

    assert {:ok, RepositoryRead} = AdapterRegistry.tool("repository.read")
    assert {:ok, OpenSpecRead} = AdapterRegistry.tool("openspec.read")

    for adapter <- [RepositoryRead, OpenSpecRead] do
      tool_manifest = adapter.manifest()
      assert tool_manifest.external_write == false
      assert tool_manifest.raw_retention == false
      assert tool_manifest.credential_kinds == []
      assert tool_manifest.approval_required == false
    end

    refute function_exported?(OpenSpecRead, :run, 2)
    refute function_exported?(RepositoryRead, :write, 2)
  end

  test "repository reads deny traversal, unpinned revisions, and paths outside the allowlist" do
    assert {:error, {:terminal, :repository_path_forbidden}} =
             RepositoryRead.invoke(
               tool_input("repository.read", ["agent.tool.read", "repository.read"], %{
                 path: "../mix.exs",
                 revision: String.duplicate("a", 40)
               })
             )

    assert {:error, {:terminal, :repository_revision_invalid}} =
             RepositoryRead.invoke(
               tool_input("repository.read", ["agent.tool.read", "repository.read"], %{
                 path: "openspec/project.md",
                 revision: "HEAD"
               })
             )

    assert {:error, {:terminal, :repository_path_forbidden}} =
             RepositoryRead.invoke(
               tool_input("repository.read", ["agent.tool.read", "repository.read"], %{
                 path: "mix.exs",
                 revision: String.duplicate("a", 40)
               })
             )
  end

  test "OpenSpec reads deny mutation commands, arbitrary flags, and shell-shaped targets" do
    assert {:error, {:terminal, :unsupported_openspec_action}} =
             OpenSpecRead.invoke(
               tool_input("openspec.read", ["agent.tool.read", "openspec.read"], %{
                 action: "archive"
               })
             )

    assert {:error, {:terminal, :invalid_openspec_target}} =
             OpenSpecRead.invoke(
               tool_input("openspec.read", ["agent.tool.read", "openspec.read"], %{
                 action: "show",
                 target: "change --flags"
               })
             )

    assert {:error, {:terminal, :invalid_tool_input}} =
             OpenSpecRead.invoke(
               tool_input("openspec.read", ["agent.tool.read", "openspec.read"], %{
                 action: "list",
                 flags: ["--json", "&&", "touch", "/tmp/not-allowed"]
               })
             )
  end

  test "OpenSpec reads dispatch exact allowlisted argv with bounded execution and no shell" do
    Application.put_env(
      :office_graph,
      :agent_runtime_command_runner,
      CapturingCommandRunner
    )

    cases = [
      {%{action: "list"}, ["list", "--json"]},
      {%{action: "show", target: "implement-internal-agent-runtime"},
       ["show", "implement-internal-agent-runtime", "--json"]},
      {%{action: "status", target: "implement-internal-agent-runtime"},
       ["status", "--change", "implement-internal-agent-runtime", "--json"]},
      {%{action: "validate", target: "implement-internal-agent-runtime"},
       ["validate", "implement-internal-agent-runtime", "--strict"]}
    ]

    for {payload, expected_argv} <- cases do
      assert {:ok, output} =
               OpenSpecRead.invoke(
                 tool_input(
                   "openspec.read",
                   ["agent.tool.read", "openspec.read"],
                   payload
                 )
               )

      assert output.classification == :observation

      assert_receive {:command_run, "openspec", ^expected_argv, opts}
      assert opts[:timeout_ms] == 1_000
      assert opts[:max_bytes] == 64 * 1_024
      assert is_binary(opts[:cd])
      refute Keyword.has_key?(opts, :shell)
    end
  end

  defp tool_input(tool_key, capabilities, adapter_payload) do
    %ToolInput{
      request_id: Ecto.UUID.generate(),
      execution_id: Ecto.UUID.generate(),
      step_key: "denial:test",
      context_package_id: Ecto.UUID.generate(),
      authority_snapshot_id: Ecto.UUID.generate(),
      operation_id: Ecto.UUID.generate(),
      tool_key: tool_key,
      adapter_version: "1",
      idempotency_key: "denial-#{Ecto.UUID.generate()}",
      capability_keys: capabilities,
      credential_kinds: [],
      timeout_ms: 1_000,
      budget_units: 64 * 1_024,
      sensitivity: :internal,
      external_write: false,
      approval_granted?: false,
      adapter_payload: adapter_payload
    }
  end
end
