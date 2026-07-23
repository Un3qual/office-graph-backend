defmodule OfficeGraph.Architecture.AshBoundaryHeuristicsTest do
  use OfficeGraph.TestSupport.AshConformanceSupport

  @support_modules [
    "test/support/office_graph/ash_authorization_support.ex",
    "test/support/office_graph/ash_conformance_support.ex",
    "test/support/office_graph/concurrency_support.ex",
    "test/support/office_graph/operator_projection_support.ex",
    "test/support/office_graph/work_packet_command_loop_support.ex"
  ]

  test "shared support macros do not inject helper implementations" do
    for path <- @support_modules do
      assert definitions_inside_using_macro(path) == [],
             "#{path} must compile helpers once and import them instead of injecting definitions"
    end
  end

  test "WorkGraph public boundary delegates to focused command and query modules" do
    for module <- @expected_work_graph_internal_modules do
      assert Code.ensure_loaded?(module), "#{inspect(module)} must exist"
    end

    source = File.read!("lib/office_graph/work_graph.ex")

    assert source =~ "defdelegate get_verification_check"
    assert source =~ "to: Queries"
    assert source =~ "defdelegate create_signal"
    assert source =~ "defdelegate create_task"
    assert source =~ "defdelegate create_review_finding"
    assert source =~ "defdelegate create_verification_check"
    assert source =~ "to: ProposalCommands"
    assert source =~ "defdelegate complete_verification"
    assert source =~ "defdelegate satisfy_verification_check_from_evidence"
    assert source =~ "to: VerificationCommands"
    refute source =~ "Repo.transaction"
    refute source =~ "Ash."
  end

  test "WorkGraph proposal commands rely on Ash create changes for parent validation" do
    proposal_source = File.read!("lib/office_graph/work_graph/proposal_commands.ex")
    review_finding_source = File.read!("lib/office_graph/work_graph/review_finding.ex")
    verification_check_source = File.read!("lib/office_graph/work_graph/verification_check.ex")

    refute proposal_source =~ "Support.validate_scope!(session_context, task)"
    refute proposal_source =~ "Support.validate_scope!(session_context, review_finding)"
    refute proposal_source =~ "Support.validate_open_task!"
    refute proposal_source =~ "Support.validate_open_review_finding!"

    assert review_finding_source =~
             "OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences"

    assert review_finding_source =~
             "OfficeGraph.WorkGraph.ReviewFinding.ValidateOpenTask"

    assert verification_check_source =~
             "OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences"

    assert verification_check_source =~
             "OfficeGraph.WorkGraph.VerificationCheck.ValidateOpenReviewFinding"
  end

  test "same-scope reference validation uses Ash for all configured references" do
    source = File.read!("lib/office_graph/work_graph/changes/validate_same_scope_references.ex")

    refute source =~ "fetch_unconverted_reference"
    refute source =~ "Repo.get"
    refute source =~ "@unconverted_reference_schemas"
  end

  @tag :source_boundary_heuristic
  test "verification calls only the supported Runs recomputation boundary" do
    runs_calls =
      remote_function_calls_in_file("lib/office_graph/verification.ex", :Runs)

    assert {:apply_accepted_verification_result, 2} in runs_calls

    for retired_name <- [
          :satisfy_required_check_and_verify_run,
          :set_run_verification_failed
        ] do
      refute Enum.any?(runs_calls, &(elem(&1, 0) == retired_name))
    end
  end

  test "verification completion centralizes parent-before-child lock acquisition" do
    source = File.read!("lib/office_graph/work_graph/verification_commands.ex")

    assert source =~ "lock_completion_graph!(session_context, verification_check.id)"
    assert source =~ "lock_review_findings_for_task!("
    assert source =~ "lock_verification_checks_for_findings!("
  end

  test "direct child create validations lock parents before accepting" do
    review_finding_source = File.read!("lib/office_graph/work_graph/review_finding.ex")
    verification_check_source = File.read!("lib/office_graph/work_graph/verification_check.ex")

    assert review_finding_source =~ "Ash.Changeset.before_action"
    assert review_finding_source =~ "Ash.Query.lock(:for_update)"

    assert verification_check_source =~ "Ash.Changeset.before_action"
    assert verification_check_source =~ "Ash.Query.lock(:for_update)"
  end

  test "packet handoff required-check validation locks current check state" do
    work_packets_source = File.read!("lib/office_graph/work_packets.ex")
    run_start_source = File.read!("lib/office_graph/runs/changes/validate_run_start_contract.ex")

    work_packet_check_read =
      work_packets_source
      |> function_body_after(
        "defp read_required_verification_checks(session_context, verification_check_ids)"
      )
      |> String.split("defp duplicate_source_graph_item_ids_error")
      |> hd()

    run_start_check_read =
      run_start_source
      |> function_body_after(
        "defp read_verification_checks(packet_version, verification_check_ids)"
      )
      |> String.split("defp validate_authority_posture")
      |> hd()

    assert work_packet_check_read =~ "Ash.Query.lock(:for_update)"
    assert run_start_check_read =~ "Ash.Query.lock(:for_update)"
  end

  test "proposed change applied transition is explicitly internal only" do
    assert %Ash.Resource.Actions.Update{public?: true} =
             Ash.Resource.Info.action(
               OfficeGraph.ProposedChanges.ProposedGraphChange,
               :mark_applied
             )

    assert Enum.any?(
             Ash.Policy.Info.policies(OfficeGraph.ProposedChanges.ProposedGraphChange),
             fn policy ->
               policy.condition == [
                 {Ash.Policy.Check.Action, [action: [:mark_applied], access_type: :filter]}
               ] and
                 Enum.any?(policy.policies, fn check ->
                   check.type == :forbid_if and
                     check.check_module == Ash.Policy.Check.Static and
                     check.check_opts[:result] == true
                 end)
             end
           )
  end

  test "shared Ash capability check is loadable" do
    assert Code.ensure_loaded?(HasCapability)

    assert HasCapability.describe(capability: :skeleton_read) =~
             "skeleton_read"
  end

  test "shared Ash capability check enforces explicit capability and target scope" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    organization_id = bootstrap.organization.id
    workspace_id = bootstrap.workspace.id

    actor = bootstrap.session
    changeset = scoped_changeset(organization_id, workspace_id)

    assert HasCapability.match?(actor, %{changeset: changeset}, capability: :skeleton_read)

    refute HasCapability.match?(actor, %{changeset: changeset}, [])

    refute HasCapability.match?(nil, %{changeset: changeset}, capability: :skeleton_read)

    refute HasCapability.match?(
             actor,
             %{changeset: scoped_changeset(Ecto.UUID.generate(), workspace_id)},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             actor,
             %{changeset: scoped_changeset(organization_id, Ecto.UUID.generate())},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             actor,
             %{changeset: %Ash.Changeset{}},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             session_context(organization_id, workspace_id, []),
             %{changeset: changeset},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             session_context(organization_id, workspace_id, ["skeleton.read"]),
             %{changeset: changeset},
             capability: :skeleton_read
           )

    assert HasCapability.match?(
             actor,
             %{query: %Ash.Query{}, action: %{type: :read}},
             capability: :skeleton_read
           )

    assert HasCapability.match?(
             actor,
             %{
               changeset: %Ash.Changeset{
                 action_type: :update,
                 data: %{organization_id: organization_id, workspace_id: workspace_id},
                 attributes: %{
                   organization_id: Ecto.UUID.generate(),
                   workspace_id: Ecto.UUID.generate()
                 }
               }
             },
             capability: :verification_complete
           )
  end

  test "direct Repo and Ecto.Multi operations are explicitly ledgered" do
    unapproved =
      direct_ecto_operations()
      |> Enum.reject(&ledger_approves_operation?(direct_ecto_ledger_entries(), &1))

    assert unapproved == [],
           """
           Found direct Repo/Ecto.Multi operations without explicit ledger approval.
           Each approval must document the file, function, and exact operation as a tuple or row in #{@architecture_exception_ledger}.

           #{format_direct_operations(unapproved)}
           """
  end

  test "direct operation scanning counts nested pattern arguments at their declared arity" do
    assert function_name(
             "def start(session_context, operation, %{run_id: run_id, graph_item_id: graph_item_id}) do"
           ) == "start/3"
  end

  test "direct Ecto exception ledger entries still point to current code" do
    operations = direct_ecto_operations()

    current_tuples =
      operations
      |> MapSet.new(&{&1.path, &1.function, &1.operation})

    missing =
      for entry <- direct_ecto_ledger_entries(),
          not MapSet.member?(current_tuples, {entry.path, entry.function, entry.operation}) do
        "#{entry.path} #{entry.function} #{entry.operation}"
      end

    assert missing == [],
           "#{@architecture_exception_ledger} contains exact direct Ecto exception tuples with no matching current code:\n#{format_errors(missing)}"
  end

  test "direct Ecto exception ledger records required approval metadata" do
    errors =
      @architecture_exception_ledger
      |> File.read!()
      |> direct_ecto_ledger_metadata_errors()

    assert errors == [],
           """
           #{@architecture_exception_ledger} entries must document owner, reason, allowed operation type, approving spec, and retirement condition:
           #{format_errors(errors)}
           """
  end

  test "implementation summary includes architecture evidence mapping" do
    assert File.exists?(@implementation_summary),
           "Expected implementation summary at #{@implementation_summary}"

    summary = File.read!(@implementation_summary)

    for required_text <- [
          "## Architecture Evidence Matrix",
          "| Requirement | Evidence | Gate |",
          "Stable WorkGraph resources are Ash-backed",
          "WorkGraph Ash actions are authorization-aware",
          "Graph identity plus typed resource creation is atomic",
          "Stable product mutations route through Ash or approved exceptions",
          "Direct Ecto paths are approved and documented",
          "Architecture gate is part of backend verification",
          "OpenSpec remains valid and mapped to evidence",
          "mix architecture.conformance",
          "./bin/verify-backend",
          "openspec validate --specs --strict",
          "openspec validate --changes --strict"
        ] do
      assert summary =~ required_text,
             "#{@implementation_summary} must include architecture evidence mapping for #{inspect(required_text)}"
    end
  end
end
