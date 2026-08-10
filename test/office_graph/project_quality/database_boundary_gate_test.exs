defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryGateTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.ProjectQuality.{DatabaseBoundaryGate, DatabaseBoundaryScanner}

  test "accepts a current occurrence with an exact approved exception" do
    current = [occurrence("sha256:current")]
    approved = [approved_entry("sha256:current")]

    assert DatabaseBoundaryGate.compare(current, approved) == []
  end

  test "does not allow an exact fingerprint to approve unresolved SQL" do
    current = [Map.put(occurrence("sha256:current"), :approval, :unresolved_sql)]
    approved = [approved_entry("sha256:current")]

    [diagnostic] = DatabaseBoundaryGate.compare(current, approved)

    assert diagnostic.kind == :unresolved
    assert diagnostic.approval == :unresolved_sql
    assert diagnostic.fingerprint == "sha256:current"
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

  test "rejects duplicate approved locators before matching fingerprints" do
    approved = [approved_entry("sha256:recorded"), approved_entry("sha256:current")]

    [diagnostic] =
      DatabaseBoundaryGate.compare(
        [occurrence("sha256:current")],
        approved
      )

    assert diagnostic.kind == :invalid_inventory
    assert diagnostic.inventory == :approved_exceptions
    assert diagnostic.entries == [1, 2]

    assert diagnostic.duplicate_locator == %{
             class: "direct_ecto",
             construct: "Repo.transaction",
             function: "persist/1",
             line: 3,
             ordinal: 1,
             path: "lib/example.ex"
           }
  end

  test "rejects incomplete terminal-object approval metadata" do
    approved =
      approved_entry("sha256:current")
      |> Map.put("terminal_objects", [
        %{"class" => "routine", "identity" => "touch_child()"}
      ])

    [diagnostic] = DatabaseBoundaryGate.compare([occurrence("sha256:current")], [approved])

    assert diagnostic.kind == :invalid_inventory
    assert diagnostic.inventory == :approved_exceptions
    assert diagnostic.entry == 1
    assert diagnostic.invalid_fields == ["terminal_objects"]
  end

  test "accepts exact RLS state terminal-object approval metadata" do
    approved =
      approved_entry("sha256:current")
      |> Map.put("terminal_objects", [
        %{
          "class" => "RLS state",
          "identity" => "children",
          "fingerprint" =>
            "sha256:0000000000000000000000000000000000000000000000000000000000000000"
        }
      ])

    assert DatabaseBoundaryGate.compare([occurrence("sha256:current")], [approved]) == []
  end

  test "rejects non-map approved exceptions without crashing the boundary gate" do
    [diagnostic] = DatabaseBoundaryGate.compare([], [nil])

    assert diagnostic.kind == :invalid_inventory
    assert diagnostic.inventory == :approved_exceptions
    assert diagnostic.entry == 1
    assert "fingerprint" in diagnostic.missing_fields
  end

  test "requires an exact approval to match both fingerprint and locator" do
    copied_occurrence = Map.put(occurrence("sha256:current"), :path, "lib/copied_example.ex")

    [diagnostic] =
      DatabaseBoundaryGate.compare(
        [occurrence("sha256:current"), copied_occurrence],
        [approved_entry("sha256:current")]
      )

    assert diagnostic.kind == :new
    assert diagnostic.fingerprint == "sha256:current"
    assert diagnostic.path == "lib/copied_example.ex"
  end

  test "does not let an approval follow an occurrence to another source line" do
    moved_occurrence = Map.put(occurrence("sha256:current"), :line, 4)

    diagnostics =
      DatabaseBoundaryGate.compare(
        [moved_occurrence],
        [approved_entry("sha256:current")]
      )

    assert Enum.map(diagnostics, &{&1.kind, &1.line}) == [new: 4, stale: 3]
  end

  test "current repository matches the reviewed database exceptions" do
    assert DatabaseBoundaryGate.check_repository(File.cwd!()) == []
  end

  test "rejects approved exceptions without exact evidence in their accepted OpenSpec change" do
    Enum.each(
      [missing_change: :missing_change, unrelated_record: :unrecorded_exception],
      fn {scenario, expected_reason} ->
        with_boundary_repository(fn root, source, occurrence ->
          approved = approved_entry(occurrence)

          inventory_path =
            Path.join(
              root,
              "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json"
            )

          File.mkdir_p!(Path.dirname(inventory_path))

          File.write!(
            inventory_path,
            Jason.encode!(%{"version" => 1, "exceptions" => [approved]})
          )

          if scenario == :unrelated_record do
            change_root =
              Path.join(root, "openspec/changes/archive/2026-08-01-approved-change")

            File.mkdir_p!(change_root)

            File.write!(
              Path.join(change_root, "database-exception-approvals.json"),
              Jason.encode!(%{
                "version" => 1,
                "approvals" => [Map.put(approved, "fingerprint", "sha256:unrelated")]
              })
            )
          end

          source_path = Path.join(root, occurrence.path)
          File.mkdir_p!(Path.dirname(source_path))
          File.write!(source_path, source)
          {_output, 0} = System.cmd("git", ["add", "."], cd: root)

          [diagnostic] = DatabaseBoundaryGate.check_repository(root)

          assert diagnostic.kind == :invalid_approval_provenance
          assert diagnostic.inventory == :approved_exceptions
          assert diagnostic.entry == 1
          assert diagnostic.approving_change == "approved-change"
          assert diagnostic.fingerprint == occurrence.fingerprint
          assert diagnostic.reason == expected_reason
        end)
      end
    )
  end

  test "matches only the exact dated archive directory for approval evidence" do
    with_boundary_repository(fn root, source, occurrence ->
      approved = approved_entry(occurrence)

      inventory_path =
        Path.join(root, "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json")

      File.mkdir_p!(Path.dirname(inventory_path))
      File.write!(inventory_path, Jason.encode!(%{"version" => 1, "exceptions" => [approved]}))

      exact_change_root =
        Path.join(root, "openspec/changes/archive/2026-08-01-approved-change")

      suffix_overlap_root =
        Path.join(root, "openspec/changes/archive/2026-07-29-integrate-approved-change")

      File.mkdir_p!(exact_change_root)
      File.mkdir_p!(suffix_overlap_root)

      File.write!(
        Path.join(exact_change_root, "database-exception-approvals.json"),
        Jason.encode!(%{"version" => 1, "approvals" => [approved]})
      )

      source_path = Path.join(root, occurrence.path)
      File.mkdir_p!(Path.dirname(source_path))
      File.write!(source_path, source)
      {_output, 0} = System.cmd("git", ["add", "."], cd: root)

      assert DatabaseBoundaryGate.check_repository(root) == []
    end)
  end

  test "compiled suppression preserves unmatched occurrence multiplicity" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_database_boundary_multiplicity_#{System.unique_integer([:positive])}"
      )

    suffix = System.unique_integer([:positive])
    macro_module = Module.concat(OfficeGraph, "BoundaryMacro#{suffix}")
    target_module = Module.concat(OfficeGraph, "BoundaryTarget#{suffix}")
    macro_path = Path.join(System.tmp_dir!(), "office_graph_boundary_macro_#{suffix}.ex")
    source_path = Path.join(root, "lib/example.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    on_exit(fn -> File.rm(macro_path) end)
    {_output, 0} = System.cmd("git", ["init", "--quiet"], cd: root)

    File.write!(macro_path, """
    defmodule #{inspect(macro_module)} do
      defmacro persist(value) do
        line = __CALLER__.line

        quote line: line do
          OfficeGraph.Repo.transaction(fn -> unquote(value) end)
        end
      end
    end
    """)

    macro_ebin = Path.join(System.tmp_dir!(), "office_graph_boundary_macro_ebin_#{suffix}")
    File.mkdir_p!(macro_ebin)
    on_exit(fn -> File.rm_rf!(macro_ebin) end)

    assert {_output, 0} =
             System.cmd("elixirc", ["-o", macro_ebin, macro_path], stderr_to_stdout: true)

    source = """
    defmodule #{inspect(target_module)} do
      require #{inspect(macro_module)}
      def persist(value), do: (OfficeGraph.Repo.transaction(fn -> value end); #{inspect(macro_module)}.persist(value))
    end
    """

    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)
    File.write!(source_path, source)

    assert {_output, 0} =
             System.cmd(
               "elixirc",
               ["-pa", macro_ebin, "-o", ebin, source_path],
               stderr_to_stdout: true
             )

    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([%{path: "lib/example.ex", source: source}])

    approved = approved_entry(occurrence)

    inventory_path =
      Path.join(root, "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json")

    evidence_path =
      Path.join(root, "openspec/changes/approved-change/database-exception-approvals.json")

    File.mkdir_p!(Path.dirname(inventory_path))
    File.mkdir_p!(Path.dirname(evidence_path))
    File.write!(inventory_path, Jason.encode!(%{"version" => 1, "exceptions" => [approved]}))
    File.write!(evidence_path, Jason.encode!(%{"version" => 1, "approvals" => [approved]}))
    {_output, 0} = System.cmd("git", ["add", "."], cd: root)

    [diagnostic] = DatabaseBoundaryGate.check_repository(root)

    assert diagnostic.kind == :compiled_reference
    assert diagnostic.construct == "Repo.transaction"
    assert diagnostic.ordinal == 2
  end

  test "accepts exact approval evidence from the active OpenSpec change before archival" do
    with_boundary_repository(fn root, source, occurrence ->
      approved = approved_entry(occurrence)

      inventory_path =
        Path.join(root, "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json")

      File.mkdir_p!(Path.dirname(inventory_path))
      File.write!(inventory_path, Jason.encode!(%{"version" => 1, "exceptions" => [approved]}))

      evidence_path =
        Path.join(
          root,
          "openspec/changes/approved-change/database-exception-approvals.json"
        )

      File.mkdir_p!(Path.dirname(evidence_path))
      File.write!(evidence_path, Jason.encode!(%{"version" => 1, "approvals" => [approved]}))

      source_path = Path.join(root, occurrence.path)
      File.mkdir_p!(Path.dirname(source_path))
      File.write!(source_path, source)
      {_output, 0} = System.cmd("git", ["add", "."], cd: root)

      assert DatabaseBoundaryGate.check_repository(root) == []
    end)
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

  defp approved_entry(fingerprint) when is_binary(fingerprint) do
    occurrence(fingerprint)
    |> approved_entry()
  end

  defp approved_entry(occurrence) when is_map(occurrence) do
    occurrence
    |> stringify_keys()
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

  defp with_boundary_repository(test) do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_database_boundary_gate_#{System.unique_integer([:positive])}"
      )

    source = """
    defmodule Example do
      def persist(value), do: OfficeGraph.Repo.transaction(fn -> value end)
    end
    """

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {_output, 0} = System.cmd("git", ["init", "--quiet"], cd: root)

    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([%{path: "lib/example.ex", source: source}])

    test.(root, source, occurrence)
  end
end
