defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryGateTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.ProjectQuality.{DatabaseBoundaryGate, DatabaseBoundaryScanner}

  test "accepts a current occurrence recorded only as removal debt" do
    current = [occurrence("sha256:current")]
    debt = [debt_entry("sha256:current")]

    assert DatabaseBoundaryGate.compare(current, debt, []) == []
  end

  test "accepts nullable function metadata for macro and module-level occurrences" do
    current = [occurrence("sha256:current") |> Map.put(:function, nil)]
    debt = [debt_entry("sha256:current") |> Map.put("function", nil)]

    assert DatabaseBoundaryGate.compare(current, debt, []) == []
  end

  test "reports an unclassified current occurrence as new" do
    [diagnostic] = DatabaseBoundaryGate.compare([occurrence("sha256:new")], [], [])

    assert diagnostic.kind == :new
    assert diagnostic.path == "lib/example.ex"
    assert diagnostic.construct == "Repo.transaction"
  end

  test "reports a fingerprint mismatch at the same locator as changed" do
    [diagnostic] =
      DatabaseBoundaryGate.compare(
        [occurrence("sha256:changed")],
        [debt_entry("sha256:recorded")],
        []
      )

    assert diagnostic.kind == :changed
    assert diagnostic.fingerprint == "sha256:changed"
    assert diagnostic.recorded_fingerprint == "sha256:recorded"
  end

  test "reports an inventory entry with no current occurrence as stale" do
    [diagnostic] =
      DatabaseBoundaryGate.compare([], [debt_entry("sha256:removed")], [])

    assert diagnostic.kind == :stale
    assert diagnostic.fingerprint == "sha256:removed"
  end

  test "rejects approved exceptions without exact approval metadata" do
    approved =
      occurrence("sha256:approved")
      |> stringify_keys()
      |> Map.merge(%{
        "owner" => "OfficeGraph.Example",
        "approving_change" => "approved-change"
      })

    [diagnostic] =
      DatabaseBoundaryGate.compare([occurrence("sha256:approved")], [], [approved])

    assert diagnostic.kind == :invalid_inventory
    assert diagnostic.inventory == :approved_exceptions

    assert diagnostic.missing_fields == [
             "reason",
             "retirement_condition",
             "verification"
           ]
  end

  test "expands compact file-grouped debt inventory entries" do
    debt =
      DatabaseBoundaryGate.decode_debt_inventory!(%{
        "version" => 1,
        "status" => "unapproved_removal_debt",
        "occurrence_fields" => [
          "fingerprint",
          "class",
          "construct",
          "function",
          "ordinal"
        ],
        "files" => [
          %{
            "path" => "lib/example.ex",
            "owner" => "OfficeGraph.Example",
            "remediation_change" => "remove-direct-database-access",
            "occurrences" => [
              ["sha256:current", "direct_ecto", "Repo.transaction", "persist/1", 1]
            ]
          }
        ]
      })

    assert debt == [
             %{
               "class" => "direct_ecto",
               "construct" => "Repo.transaction",
               "fingerprint" => "sha256:current",
               "function" => "persist/1",
               "ordinal" => 1,
               "owner" => "OfficeGraph.Example",
               "path" => "lib/example.ex",
               "remediation_change" => "remove-direct-database-access"
             }
           ]
  end

  test "builds removal-debt groups with domain owners and remediation changes" do
    inventory =
      DatabaseBoundaryGate.build_debt_inventory([
        occurrence("sha256:runtime")
        |> Map.put(:path, "lib/office_graph/runs.ex"),
        occurrence("sha256:migration")
        |> Map.put(:path, "priv/repo/migrations/20260728000000_example.exs")
      ])

    assert inventory["status"] == "unapproved_removal_debt"

    assert Enum.map(inventory["files"], &Map.take(&1, ["owner", "remediation_change"])) == [
             %{
               "owner" => "OfficeGraph.Runs",
               "remediation_change" => "remove-direct-database-access"
             },
             %{
               "owner" => "OfficeGraph.Repo.Migrations",
               "remediation_change" => "rebaseline-unreleased-migrations"
             }
           ]
  end

  test "current repository matches the reviewed database-access inventories" do
    assert DatabaseBoundaryGate.check_repository(File.cwd!()) == []
  end

  test "completed foundation slices contain no direct database access" do
    sources =
      Enum.map(
        [
          "lib/office_graph/authorization.ex",
          "lib/office_graph/content.ex",
          "lib/office_graph/identity.ex",
          "lib/office_graph/identity/services/external_identity_reconciliation.ex",
          "lib/office_graph/identity/services/human_sessions.ex",
          "lib/office_graph/integrations.ex",
          "lib/office_graph/proposed_changes.ex",
          "lib/office_graph/tenancy.ex"
        ],
        fn path ->
          %{path: path, source: File.read!(path)}
        end
      )

    assert DatabaseBoundaryScanner.scan_sources(sources) == []
  end

  test "reports remediation progress by owner and construct class" do
    debt = [
      debt_entry("sha256:transaction"),
      debt_entry("sha256:query")
      |> Map.merge(%{
        "class" => "raw_sql",
        "construct" => "Repo.query!",
        "owner" => "OfficeGraph.Identity",
        "path" => "lib/office_graph/identity.ex"
      }),
      debt_entry("sha256:migration")
      |> Map.merge(%{
        "class" => "raw_sql",
        "construct" => "migration.execute",
        "owner" => "OfficeGraph.Repo.Migrations",
        "path" => "priv/repo/migrations/example.exs",
        "remediation_change" => "rebaseline-unreleased-migrations"
      })
    ]

    assert DatabaseBoundaryGate.remediation_progress(
             debt,
             "remove-direct-database-access"
           ) == %{
             total: 2,
             by_class: %{"direct_ecto" => 1, "raw_sql" => 1},
             by_owner: [
               %{owner: "OfficeGraph.Example", total: 1},
               %{owner: "OfficeGraph.Identity", total: 1}
             ]
           }
  end

  test "rejects removal debt after its remediation change is archived" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_completed_remediation_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)

    File.mkdir_p!(
      Path.join(
        root,
        "openspec/changes/archive/2026-07-28-remove-direct-database-access"
      )
    )

    assert [
             %{
               kind: :completed_remediation_debt,
               remediation_change: "remove-direct-database-access",
               count: 1
             }
           ] =
             DatabaseBoundaryGate.completed_remediation_diagnostics(
               root,
               [debt_entry("sha256:leftover")]
             )
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

  defp debt_entry(fingerprint) do
    occurrence(fingerprint)
    |> stringify_keys()
    |> Map.drop(["line"])
    |> Map.merge(%{
      "owner" => "OfficeGraph.Example",
      "remediation_change" => "remove-direct-database-access"
    })
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {:class, value} -> {"class", to_string(value)}
      {key, value} -> {to_string(key), value}
    end)
  end
end
