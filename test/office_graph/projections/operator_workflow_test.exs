defmodule OfficeGraph.Projections.OperatorWorkflowTest do
  use OfficeGraph.DataCase, async: false

  import Ecto.Query

  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.OperatorCommandFixtures
  alias OfficeGraph.Projections
  alias OfficeGraph.QueryCounter
  alias OfficeGraph.Repo
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Runs
  alias OfficeGraph.SessionCaseHelpers
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph

  test "operator inbox exposes pending manual intake as actionable triage" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "pending-triage")

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert inbox.empty? == false
    assert inbox.source_watermark == intake.normalized_event.operation_id

    assert [row] = inbox.rows
    assert row.typed_id == %{type: "normalized_intake_event", id: intake.normalized_event.id}
    assert row.status == "pending_triage"
    assert row.reason_codes == []
    assert row.blocker_reasons == []
    assert row.allowed_next_actions == ["apply_proposed_changes"]
    normalized_event_id = intake.normalized_event.id
    proposed_change_ids = Enum.map(intake.proposed_changes, & &1.id)

    assert [
             %{
               identity: "apply_proposed_changes",
               state: "enabled",
               reason_codes: [],
               blocker_reasons: [],
               safe_explanation: "Apply pending proposed changes for this intake.",
               required_fields: ["normalized_event_id", "proposed_change_ids"],
               input_defaults: [
                 %{
                   field: "normalized_event_id",
                   value: ^normalized_event_id,
                   values: []
                 },
                 %{
                   field: "proposed_change_ids",
                   value: nil,
                   values: ^proposed_change_ids
                 }
               ],
               target_ids: [
                 %{type: "normalized_intake_event", id: ^normalized_event_id}
               ],
               trace_links: [],
               decision_links: []
             }
           ] = row.command_affordances

    assert row.operation_watermark == intake.normalized_event.operation_id

    assert row.source == %{
             identity: "manual:pending-triage",
             replay_identity: "paste:pending-triage",
             outcome: "accepted"
           }

    assert row.proposed_change_status == %{
             pending: 4,
             applied: 0,
             rejected: 0,
             total: 4
           }

    assert row.graph_links == []
    assert row.audit_trace == %{operation_id: nil, resource_count: 0, resources: []}
    assert row.revision_trace == %{operation_id: nil, resource_count: 0, resources: []}
  end

  test "operator workflow command affordances require command capabilities" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "read-only-apply")
    read_only_session = create_session_with_capabilities!(bootstrap, ["skeleton.read"])

    assert {:ok, inbox} = Projections.operator_inbox(read_only_session)
    assert row = Enum.find(inbox.rows, &(&1.normalized_event_id == intake.normalized_event.id))

    assert row.status == "pending_triage"
    assert row.allowed_next_actions == []

    assert [
             %{
               identity: "apply_proposed_changes",
               state: "hidden",
               reason_codes: ["policy_restricted"],
               blocker_reasons: ["policy_restricted"],
               safe_explanation: "This command is not available for the current operator.",
               target_ids: []
             }
           ] = row.command_affordances

    refute inspect(row.command_affordances) =~ "proposed_change.apply"
  end

  test "operator workflow item exposes applied graph links and traces" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "applied-triage")
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.status == "ready_for_packet"
    assert detail.allowed_next_actions == ["create_work_packet"]
    assert detail.blocker_reasons == []
    assert [prepare_command] = detail.command_affordances
    assert prepare_command.identity == "create_work_packet"
    assert prepare_command.state == "enabled"
    assert prepare_command.reason_codes == []
    assert prepare_command.blocker_reasons == []
    assert prepare_command.safe_explanation == "Prepare a work packet from the applied intake."

    assert prepare_command.required_fields == [
             "title",
             "objective",
             "context_summary",
             "requirements",
             "success_criteria",
             "autonomy_posture",
             "source_graph_item_ids",
             "verification_check_ids"
           ]

    assert %{type: "operation", id: detail.audit_trace.operation_id} in prepare_command.trace_links
    assert prepare_command.decision_links == []

    graph_link_types = Enum.map(detail.graph_links, & &1.type)
    assert graph_link_types == ["signal", "task", "review_finding", "verification_check"]

    assert Enum.find(detail.graph_links, &(&1.type == "signal")).id == applied.signal.id
    assert Enum.find(detail.graph_links, &(&1.type == "task")).id == applied.task.id

    assert Enum.find(detail.graph_links, &(&1.type == "review_finding")).id ==
             applied.review_finding.id

    assert Enum.find(detail.graph_links, &(&1.type == "verification_check")).id ==
             applied.verification_check.id

    assert %{type: "verification_check", id: applied.verification_check.id} in prepare_command.target_ids

    assert Enum.map(detail.graph_relationships, & &1.relationship_type) == [
             "produced_task",
             "has_review_finding",
             "requires_verification"
           ]

    assert detail.audit_trace.resource_count == 4
    assert detail.revision_trace.resource_count == 4
  end

  test "operator workflow item links packet-backed runs for applied checks" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "run-linked-triage")
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
    {:ok, run_result} = create_ready_run(bootstrap.session, applied.verification_check)

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert work_run_link = Enum.find(detail.graph_links, &(&1.type == "work_run"))
    assert work_run_link.id == run_result.run.id
    assert work_run_link.graph_item_id == nil
    assert work_run_link.state == run_result.run.aggregate_state
  end

  test "operator inbox query count stays bounded across applied rows and graph resources" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    for index <- 1..3 do
      key = "query-scaling-#{index}"
      {:ok, intake} = submit_manual_intake(bootstrap.session, key)
      {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
      {:ok, _run_result} = create_ready_run(bootstrap.session, applied.verification_check)
    end

    {{:ok, inbox}, queries} =
      QueryCounter.count(fn -> Projections.operator_inbox(bootstrap.session) end)

    assert length(inbox.rows) >= 3

    # Accepted budget: each known projection source is read at most once as rows,
    # applied operations, graph resources, packet links, and runs grow.
    assert QueryCounter.source_count(queries, "proposed_graph_changes") <= 1
    assert QueryCounter.source_count(queries, "audit_records") <= 1
    assert QueryCounter.source_count(queries, "revisions") <= 1
    assert QueryCounter.source_count(queries, "signals") <= 1
    assert QueryCounter.source_count(queries, "tasks") <= 1
    assert QueryCounter.source_count(queries, "review_findings") <= 1
    assert QueryCounter.source_count(queries, "verification_checks") <= 1
    assert QueryCounter.source_count(queries, "work_packet_version_required_checks") <= 1
    assert QueryCounter.source_count(queries, "work_packet_version_sources") <= 1
    assert QueryCounter.source_count(queries, "runs") <= 1
  end

  test "operator run state query count stays bounded across child collections" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    verification_checks =
      Enum.map(1..4, fn _index ->
        {:ok, verification_check} = create_required_verification_check(bootstrap.session)
        verification_check
      end)

    {:ok, run_result} = create_ready_run(bootstrap.session, verification_checks)

    verification_checks
    |> Enum.with_index(1)
    |> Enum.each(fn {verification_check, index} ->
      key = "run-state-query-scaling-#{index}"

      {:ok, observation_result} =
        record_observation(bootstrap.session, run_result.run, verification_check, key: key)

      {:ok, candidate} =
        create_evidence_candidate(
          bootstrap.session,
          run_result.run,
          verification_check,
          observation_result.observation,
          key: key
        )

      {:ok, _accepted} = accept_candidate(bootstrap.session, candidate, key: key)
    end)

    {{:ok, run_state}, queries} =
      QueryCounter.count(fn ->
        Projections.operator_run_state(bootstrap.session, run_result.run.id)
      end)

    assert length(run_state.required_checks) == 4
    assert length(run_state.observations) == 4
    assert length(run_state.evidence_candidates) == 4
    assert length(run_state.evidence_items) == 4
    assert length(run_state.verification_results) == 4
    assert QueryCounter.source_count(queries, "run_required_checks") <= 1
    assert QueryCounter.source_count(queries, "execution_observations") <= 1
    assert QueryCounter.source_count(queries, "evidence_candidates") <= 1
    assert QueryCounter.source_count(queries, "evidence_items") <= 1
    assert QueryCounter.source_count(queries, "verification_results") <= 1
  end

  test "operator inbox limits the hot path page size and exposes the next cursor" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    for index <- 1..51 do
      {:ok, _intake} = submit_manual_intake(bootstrap.session, "page-limit-#{index}")
    end

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)

    assert length(inbox.rows) == 50
    assert inbox.limit == 50
    assert inbox.after_cursor == nil
    assert inbox.has_more? == true
    assert is_binary(inbox.next_cursor)

    assert {:ok, next_page} =
             Projections.operator_inbox(bootstrap.session, after_cursor: inbox.next_cursor)

    assert length(next_page.rows) == 1
    assert next_page.limit == 50
    assert next_page.after_cursor == inbox.next_cursor
    assert next_page.has_more? == false
    assert next_page.next_cursor == nil
  end

  test "trusted session capabilities avoid auth table revalidation for projection reads" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, _intake} = submit_manual_intake(bootstrap.session, "trusted-auth-query")

    {{:ok, inbox}, queries} =
      QueryCounter.count(fn -> Projections.operator_inbox(bootstrap.session) end)

    assert inbox.empty? == false

    assert QueryCounter.source_count(queries, "capabilities") == 0
    assert QueryCounter.source_count(queries, "role_capabilities") == 0
    assert QueryCounter.source_count(queries, "roles") == 0
    assert QueryCounter.source_count(queries, "role_assignments") == 0
  end

  test "terminal linked work runs replace packet handoff status" do
    assert_terminal_linked_run_status("verified")
    assert_terminal_linked_run_status("failed")
  end

  test "newer linked work runs replace older failed run status" do
    key = "retry-linked-run-status"
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, key)
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
    {:ok, first_run_result} = create_ready_run(bootstrap.session, applied.verification_check)

    {:ok, accepted} =
      complete_linked_run(
        bootstrap.session,
        first_run_result.run,
        applied.verification_check,
        key,
        "failed"
      )

    assert accepted.work_run.aggregate_state == "failed"

    {:ok, retry_run_result} =
      start_run_for_packet_version(
        bootstrap.session,
        first_run_result.packet_version,
        key <> ":retry"
      )

    assert retry_run_result.run.aggregate_state == "running"

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.status == "running"
    assert detail.allowed_next_actions == []

    assert [retry_run_link | _older_links] =
             Enum.filter(detail.graph_links, &(&1.type == "work_run"))

    assert retry_run_link.id == retry_run_result.run.id
    assert retry_run_link.state == "running"

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert row = Enum.find(inbox.rows, &(&1.normalized_event_id == intake.normalized_event.id))
    assert row.status == "running"
    assert row.allowed_next_actions == []
  end

  test "directly satisfied checks complete the operator workflow item" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "directly-satisfied-triage")
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :verification_complete,
        idempotency_key: "directly-satisfied-triage"
      )

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               operation,
               applied.verification_check,
               %{
                 title: "Directly satisfied triage",
                 body: "Direct evidence completed the applied intake item.",
                 artifact_uri: "https://example.test/directly-satisfied-triage"
               }
             )

    assert completed.verification_check.lifecycle_state == "satisfied"

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.status == "verified"
    assert detail.allowed_next_actions == []

    assert verification_link = Enum.find(detail.graph_links, &(&1.type == "verification_check"))
    assert verification_link.id == applied.verification_check.id
    assert verification_link.state == "satisfied"

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert row = Enum.find(inbox.rows, &(&1.normalized_event_id == intake.normalized_event.id))
    assert row.status == "verified"
    assert row.allowed_next_actions == []
  end

  test "operator inbox presents duplicate intake as not actionable" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, accepted} = submit_manual_intake(bootstrap.session, "duplicate-intake")
    {:ok, duplicate} = submit_manual_intake(bootstrap.session, "duplicate-intake")

    assert duplicate.normalized_event.outcome == "duplicate"

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert [duplicate_row, accepted_row] = inbox.rows

    assert duplicate_row.typed_id == %{
             type: "normalized_intake_event",
             id: duplicate.normalized_event.id
           }

    assert duplicate_row.status == "not_actionable"
    assert duplicate_row.reason_codes == ["duplicate_intake"]
    assert duplicate_row.allowed_next_actions == ["view_existing_intake"]
    assert duplicate_row.blocker_reasons == ["duplicate_intake"]
    assert duplicate_row.duplicate_of_id == accepted.normalized_event.id

    assert accepted_row.typed_id == %{
             type: "normalized_intake_event",
             id: accepted.normalized_event.id
           }
  end

  test "packet readiness reports ready inputs and blocking reasons" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    ready_attrs = %{
      title: "Ready operator packet",
      objective: "Resolve the selected verification check.",
      context_summary: "A triaged item is ready for operator execution.",
      requirements: "Use the linked task and finding as execution context.",
      success_criteria: "The required verification check has accepted passing evidence.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [verification_check.graph_item_id],
      verification_check_ids: [verification_check.id]
    }

    assert {:ok, ready} = Projections.packet_readiness(bootstrap.session, ready_attrs)
    assert ready.ready? == true
    assert ready.status == "packet_ready"
    assert is_binary(ready.source_watermark)
    assert ready.blocker_reasons == []
    assert ready.allowed_next_actions == ["create_work_packet"]
    assert [create_packet] = ready.command_affordances
    assert create_packet.identity == "create_work_packet"
    assert create_packet.state == "enabled"
    assert create_packet.reason_codes == []
    assert create_packet.blocker_reasons == []

    assert create_packet.safe_explanation ==
             "Create a work packet from the selected sources and checks."

    assert create_packet.required_fields == [
             "title",
             "objective",
             "context_summary",
             "requirements",
             "success_criteria",
             "autonomy_posture",
             "source_graph_item_ids",
             "verification_check_ids"
           ]

    assert %{type: "graph_item", id: verification_check.graph_item_id} in create_packet.target_ids
    assert %{type: "verification_check", id: verification_check.id} in create_packet.target_ids
    assert create_packet.trace_links == []
    assert create_packet.decision_links == []
    assert packet_default_value(create_packet, "title") == "Ready operator packet"

    assert packet_default_values(create_packet, "source_graph_item_ids") == [
             verification_check.graph_item_id
           ]

    assert packet_default_values(create_packet, "verification_check_ids") == [
             verification_check.id
           ]

    assert packet_default_value(create_packet, "primary_source_graph_item_id") ==
             verification_check.graph_item_id

    assert packet_default_value(create_packet, "primary_verification_check_id") ==
             verification_check.id

    {:ok, second_verification_check} = create_required_verification_check(bootstrap.session)

    assert {:ok, reordered} =
             Projections.packet_readiness(bootstrap.session, %{
               ready_attrs
               | source_graph_item_ids: [
                   verification_check.graph_item_id,
                   second_verification_check.graph_item_id
                 ],
                 verification_check_ids: [second_verification_check.id, verification_check.id]
             })

    assert [reordered_create_packet] = reordered.command_affordances

    assert packet_default_value(reordered_create_packet, "primary_verification_check_id") ==
             second_verification_check.id

    assert packet_default_value(reordered_create_packet, "primary_source_graph_item_id") ==
             second_verification_check.graph_item_id

    assert ready.required_checks == [
             %{
               id: verification_check.id,
               graph_item_id: verification_check.graph_item_id,
               state: "required"
             }
           ]

    missing_title_attrs = Map.delete(ready_attrs, :title)

    assert {:ok, missing_title} =
             Projections.packet_readiness(bootstrap.session, missing_title_attrs)

    assert missing_title.ready? == false
    assert missing_title.status == "blocked"
    assert missing_title.allowed_next_actions == []
    assert missing_title.blocker_reasons == ["missing_title"]

    assert [
             %{
               identity: "create_work_packet",
               state: "disabled",
               reason_codes: ["missing_title"],
               blocker_reasons: ["missing_title"],
               safe_explanation:
                 "Resolve packet readiness blockers before creating a work packet."
             }
           ] = missing_title.command_affordances

    assert {:ok, blank_title} =
             Projections.packet_readiness(bootstrap.session, %{ready_attrs | title: " "})

    assert blank_title.ready? == false
    assert blank_title.status == "blocked"
    assert blank_title.allowed_next_actions == []
    assert blank_title.blocker_reasons == ["missing_title"]

    read_only_session = create_read_only_session!(bootstrap)

    assert {:ok, unauthorized} = Projections.packet_readiness(read_only_session, ready_attrs)
    assert unauthorized.ready? == false
    assert unauthorized.status == "blocked"
    assert unauthorized.allowed_next_actions == []
    assert unauthorized.blocker_reasons == ["policy_restricted"]

    assert [
             %{
               identity: "create_work_packet",
               state: "hidden",
               reason_codes: ["policy_restricted"],
               blocker_reasons: ["policy_restricted"],
               safe_explanation: "This command is not available for the current operator.",
               target_ids: []
             }
           ] = unauthorized.command_affordances

    refute inspect(unauthorized.command_affordances) =~ "work_packet_create"

    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)

    mismatched_attrs = %{ready_attrs | verification_check_ids: [unrelated_check.id]}

    assert {:ok, mismatched} = Projections.packet_readiness(bootstrap.session, mismatched_attrs)
    assert mismatched.ready? == false
    assert mismatched.status == "blocked"
    assert mismatched.allowed_next_actions == []
    assert mismatched.blocker_reasons == ["source_graph_item_check_mismatch"]

    duplicate_check_attrs = %{
      ready_attrs
      | verification_check_ids: [verification_check.id, verification_check.id]
    }

    assert {:ok, duplicate_check} =
             Projections.packet_readiness(bootstrap.session, duplicate_check_attrs)

    assert duplicate_check.ready? == false
    assert duplicate_check.status == "blocked"
    assert duplicate_check.allowed_next_actions == []
    assert duplicate_check.blocker_reasons == ["duplicate_verification_check_ids"]

    duplicate_source_attrs = %{
      ready_attrs
      | source_graph_item_ids: [
          verification_check.graph_item_id,
          verification_check.graph_item_id
        ]
    }

    assert {:ok, duplicate_source} =
             Projections.packet_readiness(bootstrap.session, duplicate_source_attrs)

    assert duplicate_source.ready? == false
    assert duplicate_source.status == "blocked"
    assert duplicate_source.allowed_next_actions == []
    assert duplicate_source.blocker_reasons == ["duplicate_source_graph_item_ids"]

    {:ok, completion_operation} =
      Operations.start_operation(bootstrap.session, :verification_complete,
        idempotency_key: "packet-readiness-satisfied-check"
      )

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               completion_operation,
               verification_check,
               %{
                 title: "Satisfied before readiness",
                 body: "Direct completion satisfies the check before packet readiness.",
                 artifact_uri: "https://example.test/packet-readiness-satisfied-check"
               }
             )

    assert completed.verification_check.lifecycle_state == "satisfied"

    assert {:ok, satisfied_check} = Projections.packet_readiness(bootstrap.session, ready_attrs)
    assert satisfied_check.ready? == false
    assert satisfied_check.status == "blocked"
    assert satisfied_check.allowed_next_actions == []
    assert satisfied_check.blocker_reasons == ["non_required_verification_check"]

    not_ready_attrs =
      Map.merge(ready_attrs, %{
        objective: "",
        context_summary: "",
        requirements: "",
        success_criteria: "",
        autonomy_posture: "fully_autonomous",
        source_graph_item_ids: [],
        verification_check_ids: []
      })

    assert {:ok, not_ready} = Projections.packet_readiness(bootstrap.session, not_ready_attrs)
    assert not_ready.ready? == false
    assert not_ready.status == "blocked"
    assert not_ready.allowed_next_actions == []

    assert not_ready.blocker_reasons == [
             "missing_objective",
             "missing_context_summary",
             "missing_requirements",
             "missing_success_criteria",
             "missing_source_graph_items",
             "missing_verification_checks",
             "unsupported_autonomy_posture"
           ]
  end

  test "packet workspace exposes run start only to authorized operators" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, packet_result} =
      OperatorCommandFixtures.create_ready_packet(
        bootstrap.session,
        [verification_check],
        %{
          title: "Ready workspace packet",
          objective: "Run selected work.",
          context_summary: "Ready context.",
          requirements: "Complete selected work.",
          success_criteria: "Required checks pass.",
          autonomy_posture: "human_supervised"
        }
      )

    assert {:ok, workspace} =
             Projections.packet_workspace(bootstrap.session, packet_result.packet.id)

    assert workspace.ready?
    assert workspace.allowed_next_actions == ["create_work_packet_version", "start_work_run"]
    assert [create_version, start_run] = workspace.command_affordances
    assert create_version.identity == "create_work_packet_version"
    assert create_version.state == "enabled"

    assert packet_default_value(create_version, "expected_current_version_id") ==
             packet_result.version.id

    assert start_run.identity == "start_work_run"
    assert start_run.state == "enabled"
    assert packet_default_value(start_run, "packet_version_id") == packet_result.version.id

    read_only_session = create_read_only_session!(bootstrap)

    assert {:ok, restricted_workspace} =
             Projections.packet_workspace(read_only_session, packet_result.packet.id)

    refute restricted_workspace.ready?
    assert restricted_workspace.blocker_reasons == ["policy_restricted"]
    assert restricted_workspace.allowed_next_actions == []
    assert [restricted_version, restricted_start] = restricted_workspace.command_affordances
    assert restricted_version.identity == "create_work_packet_version"
    assert restricted_version.state == "hidden"
    assert restricted_version.target_ids == []
    assert restricted_version.input_defaults == []
    assert restricted_start.state == "hidden"
    assert restricted_start.target_ids == []
    assert restricted_start.input_defaults == []
  end

  test "packet workspace normalizes source-check mismatch blockers" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)

    {:ok, packet_result} =
      OperatorCommandFixtures.create_ready_packet(
        bootstrap.session,
        [verification_check],
        %{
          title: "Mismatch workspace packet",
          objective: "Expose a safe blocker.",
          context_summary: "Mismatch context.",
          requirements: "Do not expose resource IDs.",
          success_criteria: "The blocker is generic.",
          autonomy_posture: "human_supervised"
        }
      )

    Repo.delete_all(
      from(check in OfficeGraph.WorkGraph.VerificationCheck,
        where: check.id == ^unrelated_check.id
      )
    )

    Repo.update_all(
      from(check in OfficeGraph.WorkGraph.VerificationCheck,
        where: check.id == ^verification_check.id
      ),
      set: [graph_item_id: unrelated_check.graph_item_id]
    )

    assert {:ok, workspace} =
             Projections.packet_workspace(bootstrap.session, packet_result.packet.id)

    assert "source_graph_item_check_mismatch" in workspace.blocker_reasons
    refute verification_check.id in workspace.blocker_reasons
  end

  test "packet create affordance is exposed only to authorized operators" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:ok, enabled} = Projections.packet_create_affordance(bootstrap.session)
    assert enabled.identity == "create_work_packet"
    assert enabled.state == "enabled"

    read_only_session = create_read_only_session!(bootstrap)

    assert {:ok, restricted} = Projections.packet_create_affordance(read_only_session)
    assert restricted.identity == "create_work_packet"
    assert restricted.state == "hidden"
    assert restricted.target_ids == []
    assert restricted.input_defaults == []
  end

  test "manual intake affordance is exposed only to authorized operators" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:ok, enabled} = Projections.manual_intake_affordance(bootstrap.session)
    assert enabled.identity == "submit_manual_intake"
    assert enabled.state == "enabled"

    read_only_session = create_read_only_session!(bootstrap)

    assert {:ok, restricted} = Projections.manual_intake_affordance(read_only_session)
    assert restricted.identity == "submit_manual_intake"
    assert restricted.state == "hidden"
    assert restricted.target_ids == []
  end

  test "operator run state moves from missing evidence to verified" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    assert {:ok, initial_state} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert initial_state.status == "awaiting_execution"
    assert is_binary(initial_state.source_watermark)

    assert initial_state.allowed_next_actions == [
             "record_execution_observation",
             "waive_verification_check"
           ]

    assert [record_observation, waive_check] = initial_state.command_affordances
    assert record_observation.identity == "record_execution_observation"
    assert record_observation.state == "enabled"
    assert record_observation.reason_codes == []
    assert record_observation.blocker_reasons == []
    assert record_observation.safe_explanation == "Record execution observations for this run."

    assert record_observation.required_fields == [
             "run_id",
             "observation_source_kind",
             "observation_source_identity",
             "observation_idempotency_key",
             "observed_status",
             "normalized_status",
             "freshness_state",
             "trust_basis",
             "verification_check_id",
             "source_graph_item_id",
             "observation_rationale"
           ]

    assert record_observation.input_defaults == [
             %{field: "run_id", value: run_result.run.id, values: []}
           ]

    assert %{type: "work_run", id: run_result.run.id} in record_observation.target_ids

    assert %{type: "verification_check", id: verification_check.id} in record_observation.target_ids

    assert waive_check.identity == "waive_verification_check"
    assert waive_check.state == "enabled"

    assert initial_state.missing_evidence == [
             %{verification_check_id: verification_check.id, reason: "missing_accepted_evidence"}
           ]

    assert [%{graph_item_id: graph_item_id}] = initial_state.required_checks
    assert graph_item_id == verification_check.graph_item_id

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "operator-run-state"
      )

    assert {:ok, awaiting_candidate} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert awaiting_candidate.status == "awaiting_evidence"

    assert awaiting_candidate.allowed_next_actions == [
             "create_evidence_candidate",
             "waive_verification_check"
           ]

    assert [create_candidate, waive_check] = awaiting_candidate.command_affordances
    assert waive_check.identity == "waive_verification_check"

    assert create_candidate.required_fields == [
             "work_run_id",
             "verification_check_id",
             "execution_observation_id",
             "claim",
             "source_kind",
             "source_identity",
             "freshness_state",
             "trust_basis",
             "sensitivity"
           ]

    assert create_candidate.input_defaults == [
             %{field: "work_run_id", value: run_result.run.id, values: []},
             %{field: "verification_check_id", value: nil, values: [verification_check.id]},
             %{
               field: "execution_observation_id",
               value: nil,
               values: [observation_result.observation.id]
             },
             %{field: "sensitivity", value: "internal", values: []}
           ]

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "operator-run-state"
      )

    assert {:ok, awaiting_evidence} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert awaiting_evidence.status == "awaiting_evidence_acceptance"

    assert awaiting_evidence.allowed_next_actions == [
             "accept_evidence",
             "waive_verification_check"
           ]

    assert [accept_evidence, waive_check] = awaiting_evidence.command_affordances
    assert waive_check.identity == "waive_verification_check"
    assert accept_evidence.identity == "accept_evidence"
    assert accept_evidence.state == "enabled"
    assert accept_evidence.reason_codes == []
    assert accept_evidence.blocker_reasons == []

    assert accept_evidence.safe_explanation ==
             "Accept a candidate as evidence for a missing check."

    assert accept_evidence.required_fields == [
             "evidence_candidate_id",
             "title",
             "body",
             "result",
             "acceptance_policy_basis"
           ]

    assert [
             %{
               id: candidate_id,
               state: "candidate",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               execution_observation_id: observation_id
             }
           ] = awaiting_evidence.evidence_candidates

    assert candidate_id == candidate.id
    assert observation_id == observation_result.observation.id
    assert %{type: "evidence_candidate", id: candidate.id} in accept_evidence.target_ids

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate, key: "operator-run-state", result: "passed")

    assert {:ok, verified_state} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    assert verified_state.status == "verified"
    assert verified_state.allowed_next_actions == []
    assert verified_state.command_affordances == []
    assert verified_state.missing_evidence == []
    assert [%{id: evidence_item_id, state: "accepted"}] = verified_state.evidence_items
    assert evidence_item_id == accepted.evidence_item.id

    assert [
             %{
               id: result_id,
               result: "passed",
               evidence_item_id: evidence_item_id,
               operation_id: operation_id,
               actor_principal_id: actor_principal_id,
               policy_basis: "owner_acceptance",
               target_graph_item_id: target_graph_item_id
             }
           ] = verified_state.verification_results

    assert result_id == accepted.verification_result.id
    assert evidence_item_id == accepted.evidence_item.id
    assert operation_id == accepted.verification_result.operation_id
    assert actor_principal_id == bootstrap.session.principal_id
    assert target_graph_item_id == verification_check.graph_item_id
  end

  test "operator run state advertises GraphQL observation and waiver commands" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    assert {:ok, run_state} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert run_state.allowed_next_actions == [
             "record_execution_observation",
             "waive_verification_check"
           ]

    assert [record_observation, waive_check] = run_state.command_affordances
    assert record_observation.identity == "record_execution_observation"
    assert waive_check.identity == "waive_verification_check"

    assert waive_check.required_fields == [
             "run_id",
             "run_required_check_id",
             "expected_execution_state",
             "expected_verification_state",
             "reason",
             "policy_basis"
           ]

    assert waive_check.input_defaults == [
             %{field: "run_id", value: run_result.run.id, values: []},
             %{
               field: "run_required_check_id",
               value: nil,
               values: Enum.map(run_result.required_checks, & &1.id)
             },
             %{
               field: "expected_execution_state",
               value: run_result.run.execution_state,
               values: []
             },
             %{
               field: "expected_verification_state",
               value: run_result.run.verification_state,
               values: []
             }
           ]
  end

  test "operator run state source watermark changes when visible child state changes" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    assert {:ok, initial_state} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "run-watermark-observation"
      )

    assert {:ok, observed_state} =
             Projections.operator_run_state(bootstrap.session, observation_result.run.id)

    refute observed_state.source_watermark == initial_state.source_watermark

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        observation_result.run,
        verification_check,
        observation_result.observation,
        key: "run-watermark-candidate"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate,
        key: "run-watermark-candidate",
        result: "passed"
      )

    assert {:ok, accepted_state} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    refute accepted_state.source_watermark == observed_state.source_watermark
  end

  test "operator run state does not offer acceptance for unusable evidence candidates" do
    for {key, overrides} <- [
          {"stale-candidate", [freshness_state: "stale"]},
          {"untrusted-candidate", [trust_basis: "unauthenticated"]}
        ] do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      {:ok, verification_check} = create_required_verification_check(bootstrap.session)
      {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

      {:ok, observation_result} =
        record_observation(bootstrap.session, run_result.run, verification_check,
          key: "operator-run-state-#{key}"
        )

      {:ok, candidate} =
        create_evidence_candidate(
          bootstrap.session,
          run_result.run,
          verification_check,
          observation_result.observation,
          Keyword.put(overrides, :key, "operator-run-state-#{key}")
        )

      assert {:ok, awaiting_evidence} =
               Projections.operator_run_state(bootstrap.session, run_result.run.id)

      assert awaiting_evidence.status == "awaiting_evidence"

      assert awaiting_evidence.allowed_next_actions == [
               "create_evidence_candidate",
               "waive_verification_check"
             ]

      assert Enum.any?(
               awaiting_evidence.evidence_candidates,
               &(&1.id == candidate.id and &1.state == "candidate")
             )
    end
  end

  test "operator run state only defaults passed-acceptance-eligible observations" do
    for {key, observation_overrides} <- [
          {"failed-observation", [normalized_status: "failed", observed_status: "failed"]},
          {"stale-observation", [freshness_state: "stale"]},
          {"untrusted-observation", [trust_basis: "unauthenticated"]}
        ] do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      {:ok, verification_check} = create_required_verification_check(bootstrap.session)
      {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

      {:ok, observation_result} =
        record_observation(
          bootstrap.session,
          run_result.run,
          verification_check,
          Keyword.put(observation_overrides, :key, key)
        )

      assert {:ok, run_state} =
               Projections.operator_run_state(bootstrap.session, observation_result.run.id)

      create_candidate =
        Enum.find(run_state.command_affordances, &(&1.identity == "create_evidence_candidate"))

      if create_candidate do
        assert packet_default_values(create_candidate, "execution_observation_id") == []
        assert packet_default_values(create_candidate, "verification_check_id") == []
      else
        assert run_state.status == "failed"
      end
    end
  end

  test "operator run state keeps acceptance action for pending candidates on missing checks" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, [first_check, second_check])

    {:ok, first_observation} =
      record_observation(bootstrap.session, run_result.run, first_check,
        key: "partial-multi-check-first"
      )

    {:ok, first_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        first_check,
        first_observation.observation,
        key: "partial-multi-check-first"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, first_candidate,
        key: "partial-multi-check-first",
        result: "passed"
      )

    {:ok, second_observation} =
      record_observation(bootstrap.session, accepted.work_run, second_check,
        key: "partial-multi-check-second"
      )

    {:ok, second_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        second_observation.run,
        second_check,
        second_observation.observation,
        key: "partial-multi-check-second"
      )

    assert {:ok, waiting_state} =
             Projections.operator_run_state(bootstrap.session, second_observation.run.id)

    assert waiting_state.status == "awaiting_evidence_acceptance"

    assert waiting_state.allowed_next_actions == [
             "accept_evidence",
             "waive_verification_check"
           ]

    assert Enum.any?(
             waiting_state.evidence_candidates,
             &(&1.id == second_candidate.id and &1.verification_check_id == second_check.id and
                 &1.state == "candidate")
           )

    assert waiting_state.missing_evidence == [
             %{verification_check_id: second_check.id, reason: "missing_accepted_evidence"}
           ]
  end

  test "operator run state exposes failed evidence without completing the workflow" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "operator-failed-run-state",
        observed_status: "failed",
        normalized_status: "failed"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "operator-failed-run-state"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate,
        key: "operator-failed-run-state",
        result: "failed"
      )

    assert {:ok, failed_state} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    assert failed_state.status == "failed"
    assert failed_state.allowed_next_actions == []

    assert failed_state.missing_evidence == [
             %{verification_check_id: verification_check.id, reason: "failed_check"}
           ]

    assert [%{id: result_id, result: "failed"}] = failed_state.verification_results
    assert result_id == accepted.verification_result.id
  end

  test "operator run state command affordances require command capabilities" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)
    read_only_session = create_session_with_capabilities!(bootstrap, ["skeleton.read"])

    assert {:ok, initial_state} =
             Projections.operator_run_state(read_only_session, run_result.run.id)

    assert initial_state.status == "awaiting_execution"
    assert initial_state.allowed_next_actions == []
    assert [record_observation] = initial_state.command_affordances
    assert record_observation.identity == "record_execution_observation"
    assert record_observation.state == "hidden"
    assert record_observation.reason_codes == ["policy_restricted"]
    assert record_observation.blocker_reasons == ["policy_restricted"]
    assert record_observation.target_ids == []
    refute inspect(record_observation) =~ "execution_observation.record"

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "read-only-run-state"
      )

    assert {:ok, awaiting_evidence} =
             Projections.operator_run_state(read_only_session, run_result.run.id)

    assert awaiting_evidence.status == "awaiting_evidence"
    assert awaiting_evidence.allowed_next_actions == []
    assert [create_candidate] = awaiting_evidence.command_affordances
    assert create_candidate.identity == "create_evidence_candidate"
    assert create_candidate.state == "hidden"
    assert create_candidate.reason_codes == ["policy_restricted"]
    assert create_candidate.blocker_reasons == ["policy_restricted"]
    assert create_candidate.target_ids == []
    refute inspect(create_candidate) =~ "evidence_candidate.create"

    {:ok, _candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "read-only-run-state"
      )

    assert {:ok, awaiting_acceptance} =
             Projections.operator_run_state(read_only_session, run_result.run.id)

    assert awaiting_acceptance.status == "awaiting_evidence_acceptance"
    assert awaiting_acceptance.allowed_next_actions == []
    assert [accept_evidence] = awaiting_acceptance.command_affordances
    assert accept_evidence.identity == "accept_evidence"
    assert accept_evidence.state == "hidden"
    assert accept_evidence.reason_codes == ["policy_restricted"]
    assert accept_evidence.blocker_reasons == ["policy_restricted"]
    assert accept_evidence.target_ids == []
    refute inspect(accept_evidence) =~ "evidence.accept"
  end

  defp submit_manual_intake(session, key) do
    {:ok, operation} =
      Operations.start_operation(session, :manual_intake_submit,
        idempotency_key: "manual-intake:#{key}:#{System.unique_integer([:positive])}"
      )

    Integrations.submit_manual_intake(session, operation, %{
      source_identity: "manual:#{key}",
      replay_identity: "paste:#{key}",
      body: "Investigate #{key} and prove the result with accepted evidence."
    })
  end

  defp apply_changes(session, proposed_changes) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)
    ProposedChanges.apply_all(session, operation, proposed_changes)
  end

  defp create_required_verification_check(session) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "Operator signal",
             body: "Operator signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "Operator task",
             body: "Operator task body."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "Operator finding",
             body: "Operator finding body."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(session, operation, review_finding, %{
             title: "Operator check",
             body: "Operator check body."
           }) do
      {:ok, verification_check}
    end
  end

  defp create_ready_run(session, verification_check) when not is_list(verification_check) do
    create_ready_run(session, [verification_check])
  end

  defp create_ready_run(session, verification_checks) when is_list(verification_checks) do
    OperatorCommandFixtures.create_ready_run(
      session,
      verification_checks,
      %{
        title: "Ready operator packet",
        objective: "Run selected work.",
        context_summary: "Ready context.",
        requirements: "Complete selected work.",
        success_criteria: "Required checks pass.",
        autonomy_posture: "human_supervised"
      },
      %{
        source_surface: "test",
        reason: "Execute ready packet.",
        authority_posture: "human_supervised"
      },
      attach_packet_version?: true
    )
  end

  defp create_read_only_session!(bootstrap) do
    create_session_with_capabilities!(bootstrap, ["skeleton.read"])
  end

  defp create_session_with_capabilities!(bootstrap, capability_keys) do
    SessionCaseHelpers.create_session_with_capabilities!(bootstrap, capability_keys,
      prefix: "operator-read-only",
      trusted?: true
    )
  end

  defp packet_default_value(command_affordance, field) do
    command_affordance.input_defaults
    |> Enum.find(&(&1.field == field))
    |> case do
      nil -> nil
      default -> default.value
    end
  end

  defp packet_default_values(command_affordance, field) do
    command_affordance.input_defaults
    |> Enum.find(&(&1.field == field))
    |> case do
      nil -> []
      default -> default.values
    end
  end

  defp start_run_for_packet_version(session, packet_version, key) do
    {:ok, run_operation} =
      Operations.start_operation(session, :work_run_start,
        idempotency_key: "work-run-operation:#{key}"
      )

    Runs.start_run(session, run_operation, packet_version, %{
      source_surface: "test",
      reason: "Retry ready packet.",
      authority_posture: "human_supervised"
    })
  end

  defp assert_terminal_linked_run_status(expected_status) do
    key = "terminal-linked-run-#{expected_status}"
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, key)
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
    {:ok, run_result} = create_ready_run(bootstrap.session, applied.verification_check)

    {:ok, accepted} =
      complete_linked_run(
        bootstrap.session,
        run_result.run,
        applied.verification_check,
        key,
        expected_status
      )

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.status == expected_status
    assert detail.allowed_next_actions == []

    assert work_run_link = Enum.find(detail.graph_links, &(&1.type == "work_run"))
    assert work_run_link.id == accepted.work_run.id
    assert work_run_link.state == expected_status

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert row = Enum.find(inbox.rows, &(&1.normalized_event_id == intake.normalized_event.id))
    assert row.status == expected_status
    assert row.allowed_next_actions == []
  end

  defp complete_linked_run(session, run, verification_check, key, "verified") do
    {:ok, observation_result} = record_observation(session, run, verification_check, key: key)

    {:ok, candidate} =
      create_evidence_candidate(session, run, verification_check, observation_result.observation,
        key: key
      )

    accept_candidate(session, candidate, key: key, result: "passed")
  end

  defp complete_linked_run(session, run, verification_check, key, "failed") do
    {:ok, observation_result} =
      record_observation(session, run, verification_check,
        key: key,
        observed_status: "failed",
        normalized_status: "failed"
      )

    {:ok, candidate} =
      create_evidence_candidate(session, run, verification_check, observation_result.observation,
        key: key
      )

    accept_candidate(session, candidate, key: key, result: "failed")
  end

  defp record_observation(session, run, verification_check, opts) do
    key = Keyword.fetch!(opts, :key)
    observed_status = Keyword.get(opts, :observed_status, "passed")
    normalized_status = Keyword.get(opts, :normalized_status, "succeeded")
    freshness_state = Keyword.get(opts, :freshness_state, "fresh")
    trust_basis = Keyword.get(opts, :trust_basis, "owner_attested")

    OperatorCommandFixtures.record_observation(
      session,
      run,
      verification_check,
      %{
        source_kind: "human",
        source_identity: "manual:#{key}",
        idempotency_key: "observation:#{key}",
        observed_status: observed_status,
        normalized_status: normalized_status,
        freshness_state: freshness_state,
        trust_basis: trust_basis,
        rationale: "Human confirmed #{key}."
      },
      idempotency_key: "observation-operation:#{key}"
    )
  end

  defp create_evidence_candidate(session, run, verification_check, observation, opts) do
    key = Keyword.fetch!(opts, :key)
    freshness_state = Keyword.get(opts, :freshness_state, "fresh")
    trust_basis = Keyword.get(opts, :trust_basis, "owner_attested")

    OperatorCommandFixtures.create_evidence_candidate(
      session,
      run,
      verification_check,
      observation,
      %{
        claim: "Evidence candidate #{key}.",
        source_kind: "human",
        source_identity: "manual:#{key}",
        freshness_state: freshness_state,
        trust_basis: trust_basis,
        sensitivity: "internal"
      },
      idempotency_key: "candidate-operation:#{key}"
    )
  end

  defp accept_candidate(session, candidate, opts) do
    key = Keyword.fetch!(opts, :key)

    {:ok, operation} =
      Operations.start_operation(session, :evidence_accept,
        idempotency_key: "accept-operation:#{key}"
      )

    Verification.accept_evidence_candidate(session, operation, candidate, %{
      title: "Accepted evidence #{key}",
      body: "Accepted evidence body #{key}.",
      result: Keyword.get(opts, :result, "passed"),
      acceptance_policy_basis: "owner_acceptance"
    })
  end
end
