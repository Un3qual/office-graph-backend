defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryGateTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.ProjectQuality.{DatabaseBoundaryGate, DatabaseBoundaryScanner}

  test "accepts a current occurrence with an exact approved exception" do
    current = [occurrence("sha256:current")]
    approved = [approved_entry("sha256:current")]

    assert DatabaseBoundaryGate.compare(current, approved) == []
  end

  test "accepts nullable function metadata for module-level occurrences" do
    current = [occurrence("sha256:current") |> Map.put(:function, nil)]
    approved = [approved_entry("sha256:current") |> Map.put("function", nil)]

    assert DatabaseBoundaryGate.compare(current, approved) == []
  end

  test "reports an unapproved current occurrence as new" do
    [diagnostic] = DatabaseBoundaryGate.compare([occurrence("sha256:new")], [])

    assert diagnostic.kind == :new
    assert diagnostic.path == "lib/example.ex"
    assert diagnostic.construct == "Repo.transaction"
  end

  test "reports a fingerprint mismatch at the same locator as changed" do
    [diagnostic] =
      DatabaseBoundaryGate.compare(
        [occurrence("sha256:changed")],
        [approved_entry("sha256:recorded")]
      )

    assert diagnostic.kind == :changed
    assert diagnostic.fingerprint == "sha256:changed"
    assert diagnostic.recorded_fingerprint == "sha256:recorded"
  end

  test "reports an approved exception with no current occurrence as stale" do
    [diagnostic] = DatabaseBoundaryGate.compare([], [approved_entry("sha256:removed")])

    assert diagnostic.kind == :stale
    assert diagnostic.fingerprint == "sha256:removed"
    assert diagnostic.inventory == :approved_exceptions
  end

  test "rejects approved exceptions without exact approval metadata" do
    approved =
      occurrence("sha256:approved")
      |> stringify_keys()
      |> Map.merge(%{
        "owner" => "OfficeGraph.Example",
        "approving_change" => "approved-change"
      })

    [diagnostic] = DatabaseBoundaryGate.compare([occurrence("sha256:approved")], [approved])

    assert diagnostic.kind == :invalid_inventory
    assert diagnostic.inventory == :approved_exceptions

    assert diagnostic.missing_fields == [
             "reason",
             "retirement_condition",
             "verification"
           ]
  end

  test "current repository matches the reviewed database exceptions" do
    assert DatabaseBoundaryGate.check_repository(File.cwd!()) == []
  end

  test "completed production slices contain no direct database access" do
    sources =
      Enum.map(
        [
          "lib/office_graph/agent_runtime.ex",
          "lib/office_graph/agent_runtime/commands/approval_commands.ex",
          "lib/office_graph/agent_runtime/commands/cancellation_commands.ex",
          "lib/office_graph/agent_runtime/commands/context_expansion_commands.ex",
          "lib/office_graph/agent_runtime/commands/invocation_commands.ex",
          "lib/office_graph/agent_runtime/workers/execution_worker.ex",
          "lib/office_graph/agent_runtime/workers/gate_expiry_worker.ex",
          "lib/office_graph/authorization.ex",
          "lib/office_graph/content.ex",
          "lib/office_graph/identity.ex",
          "lib/office_graph/identity/services/external_identity_reconciliation.ex",
          "lib/office_graph/identity/services/human_sessions.ex",
          "lib/office_graph/integrations.ex",
          "lib/office_graph/proposed_changes.ex",
          "lib/office_graph/runs.ex",
          "lib/office_graph/tenancy.ex",
          "lib/office_graph/verification.ex",
          "lib/office_graph/verification/waiver.ex",
          "lib/office_graph/work_graph/changes/validate_evidence_candidate_references.ex",
          "lib/office_graph/work_graph/commands/command_support.ex",
          "lib/office_graph/work_graph/policies/relationship_cycle_policy.ex",
          "lib/office_graph/work_packets.ex"
        ],
        fn path -> %{path: path, source: File.read!(path)} end
      )

    assert DatabaseBoundaryScanner.scan_sources(sources) == []
  end

  defp occurrence(fingerprint) do
    %{
      fingerprint: fingerprint,
      path: "lib/example.ex",
      class: :direct_ecto,
      construct: "Repo.transaction",
      function: "persist/1",
      ordinal: 1,
      line: 3
    }
  end

  defp approved_entry(fingerprint) do
    occurrence(fingerprint)
    |> stringify_keys()
    |> Map.drop(["line"])
    |> Map.merge(%{
      "approving_change" => "approved-change",
      "owner" => "OfficeGraph.Example",
      "reason" => "Required by the approved test contract.",
      "retirement_condition" => "Remove when the approved mechanism is retired.",
      "verification" => "Covered by the strict boundary gate."
    })
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {:class, value} -> {"class", to_string(value)}
      {key, value} -> {to_string(key), value}
    end)
  end
end
