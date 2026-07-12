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
  alias OfficeGraph.WorkPackets

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

    {{:ok, relationship_page}, relationship_queries} =
      QueryCounter.count(fn ->
        Projections.operator_relationship_details_page(
          bootstrap.session,
          intake.normalized_event.id,
          limit: 2,
          after_cursor: nil
        )
      end)

    assert length(relationship_page.edges) == 2

    detail_queries =
      Enum.filter(
        relationship_queries,
        &String.contains?(&1.query || "", "graph_relationships gr")
      )

    assert length(detail_queries) == 1
    assert String.contains?(hd(detail_queries).query, "graph_relationships")
    assert QueryCounter.source_count(relationship_queries, "audit_records") == 0
    assert String.contains?(hd(detail_queries).query, "LIMIT")
  end

  test "operator workflow stops offering packet creation once its packet contract exists" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "created-packet-terminal-state")
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)

    {:ok, _packet_result} =
      OperatorCommandFixtures.create_ready_packet(
        bootstrap.session,
        [applied.verification_check],
        %{
          title: "Created intake packet",
          objective: "Run the applied intake work.",
          context_summary: "The intake has an authoritative packet.",
          requirements: "Do not create the packet twice.",
          success_criteria: "The required check passes.",
          autonomy_posture: "human_supervised"
        }
      )

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.status == "packet_created"
    assert detail.allowed_next_actions == []
    assert detail.command_affordances == []
    assert packet_link = Enum.find(detail.graph_links, &(&1.type == "work_packet"))
    assert packet_link.title == "Created intake packet"
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

  @tag timeout: 120_000
  test "operator inbox batches exact relationship counts across fifty rows" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    for index <- 1..50 do
      {:ok, _intake} = submit_manual_intake(bootstrap.session, "batched-counts-#{index}")
    end

    {{:ok, inbox}, queries} =
      QueryCounter.count(fn -> Projections.operator_inbox(bootstrap.session, limit: 50) end)

    assert length(inbox.rows) == 50

    relationship_projection_queries =
      Enum.filter(queries, fn query ->
        String.contains?(query.query || "", "graph_relationships gr")
      end)

    assert length(relationship_projection_queries) == 1

    relationship_query = hd(relationship_projection_queries).query
    assert String.contains?(relationship_query, "source_matched_versions AS")

    refute Regex.match?(
             ~r/FROM requested_events\s+JOIN work_packet_versions/,
             relationship_query
           )
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
    # One bounded detail query plus one aggregate-count query per child source.
    assert QueryCounter.source_count(queries, "run_required_checks") <= 2
    assert QueryCounter.source_count(queries, "execution_observations") <= 2
    assert QueryCounter.source_count(queries, "evidence_candidates") <= 2
    assert QueryCounter.source_count(queries, "evidence_items") <= 2
    assert QueryCounter.source_count(queries, "verification_results") <= 2
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

  @tag timeout: 120_000
  test "relationship detail pages more than twenty scoped workflow links without loading history" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, older_intake} = submit_manual_intake(bootstrap.session, "older-bounded-workflow-row")
    {:ok, older_applied} = apply_changes(bootstrap.session, older_intake.proposed_changes)
    {:ok, older_run} = create_ready_run(bootstrap.session, older_applied.verification_check)

    key = "paged-workflow-links"
    {:ok, intake} = submit_manual_intake(bootstrap.session, key)
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
    {:ok, first_run} = create_ready_run(bootstrap.session, applied.verification_check)

    runs =
      Enum.reduce(2..21, [first_run.run], fn index, [current | _] = runs ->
        OfficeGraph.Repo.query!(
          "UPDATE runs SET state = 'failed', aggregate_state = 'failed', execution_state = 'failed', verification_state = 'failed' WHERE id = $1",
          [Ecto.UUID.dump!(current.id)]
        )

        {:ok, next_run} =
          start_run_for_packet_version(
            bootstrap.session,
            first_run.packet_version,
            "#{key}:#{index}"
          )

        [next_run.run | runs]
      end)

    {:ok, other_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: "Foreign workflow links",
        organization_slug: "foreign-workflow-links",
        workspace_name: "Foreign workflow links",
        workspace_slug: "foreign-workflow-links",
        initiative_name: "Foreign workflow links",
        initiative_slug: "foreign-workflow-links",
        owner_email: "foreign-workflow-links@office-graph.local"
      )

    {:ok, other_check} = create_required_verification_check(other_scope.session)
    {:ok, other_run} = create_ready_run(other_scope.session, other_check)
    cross_tenant_relationship_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO graph_relationships
        (id, source_item_id, target_item_id, relationship_type, inserted_at, updated_at)
      VALUES ($1, $2, $3, 'cross_tenant_probe', now(), now())
      """,
      [
        Ecto.UUID.dump!(cross_tenant_relationship_id),
        Ecto.UUID.dump!(applied.signal.graph_item_id),
        Ecto.UUID.dump!(other_check.graph_item_id)
      ]
    )

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.relationship_summary.graph_links == 26
    assert detail.relationship_summary.graph_relationships == 3
    assert detail.relationship_summary.has_more
    assert length(detail.graph_links) == 20

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)

    assert older_row =
             Enum.find(inbox.rows, &(&1.normalized_event_id == older_intake.normalized_event.id))

    assert Enum.any?(
             older_row.graph_links,
             &(&1.type == "work_run" and &1.id == older_run.run.id)
           )

    assert {:ok, first_page} =
             Projections.operator_relationship_details_page(
               bootstrap.session,
               intake.normalized_event.id,
               limit: 20,
               after_cursor: nil
             )

    assert first_page.has_next_page?
    assert length(first_page.edges) == 20
    assert first_page.graph_link_count == 26
    assert first_page.graph_relationship_count == 3

    assert {:ok, second_page} =
             Projections.operator_relationship_details_page(
               bootstrap.session,
               intake.normalized_event.id,
               limit: 20,
               after_cursor: List.last(first_page.edges).cursor
             )

    all_ids = Enum.map(first_page.edges ++ second_page.edges, & &1.node.stable_id)
    assert second_page.graph_link_count == 26
    assert second_page.graph_relationship_count == 3
    assert Enum.all?(runs, &("work_run:#{&1.id}" in all_ids))
    refute "work_run:#{other_run.run.id}" in all_ids
    refute cross_tenant_relationship_id in all_ids

    assert {:ok, exhausted_page} =
             Projections.operator_relationship_details_page(
               bootstrap.session,
               intake.normalized_event.id,
               limit: 20,
               after_cursor: List.last(second_page.edges).cursor
             )

    assert exhausted_page.edges == []
    assert exhausted_page.has_next_page? == false
    assert exhausted_page.has_previous_page? == true
    assert exhausted_page.graph_link_count == 26
    assert exhausted_page.graph_relationship_count == 3
  end

  @tag timeout: 120_000
  test "workflow run summary ranks once per event by run recency across packet versions" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "event-wide-run-ranking")
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)

    {:ok, packet_result} =
      create_packet_with_sources_and_checks(
        bootstrap.session,
        "event-wide-run-ranking",
        [applied.verification_check.graph_item_id],
        [applied.verification_check.id]
      )

    {:ok, initial_run} =
      start_run_for_packet_version(
        bootstrap.session,
        packet_result.version,
        "event-wide-run-ranking:1"
      )

    version_runs =
      Enum.reduce(2..23, [{packet_result.version, initial_run.run}], fn index,
                                                                        [
                                                                          {_version, current_run}
                                                                          | _
                                                                        ] =
                                                                          version_runs ->
        mark_run_failed!(current_run)

        {:ok, next_packet_result} =
          create_next_packet_version(
            bootstrap.session,
            packet_result.packet.id,
            hd(version_runs) |> elem(0),
            applied.verification_check,
            index
          )

        {:ok, next_run} =
          start_run_for_packet_version(
            bootstrap.session,
            next_packet_result.version,
            "event-wide-run-ranking:#{index}"
          )

        [{next_packet_result.version, next_run.run} | version_runs]
      end)

    {uuid_first_version, uuid_first_run} = Enum.min_by(version_runs, &elem(&1, 0).id)

    {recent_version, recent_run} =
      Enum.find(version_runs, fn {version, _run} -> version.id != uuid_first_version.id end)

    Enum.each(version_runs, fn {_version, run} -> mark_run_failed!(run) end)

    Repo.query!(
      "UPDATE runs SET inserted_at = now() - interval '2 hours' WHERE id = $1",
      [Ecto.UUID.dump!(uuid_first_run.id)]
    )

    restore_running_run!(recent_run)

    {{:ok, detail}, queries} =
      QueryCounter.count(fn ->
        Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)
      end)

    assert detail.status == recent_run.aggregate_state

    run_query = Enum.find(queries, &String.contains?(&1.query || "", "ranked_runs"))
    assert run_query
    assert String.contains?(run_query.query, "PARTITION BY event_key")
    assert String.contains?(run_query.query, "ORDER BY r.inserted_at DESC, r.id DESC")
    assert {:ok, %Postgrex.Result{num_rows: 21}} = run_query.result
    refute recent_version.id == uuid_first_version.id
  end

  test "relationship base and detail use the canonical packet link predicate" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "canonical-packet-links")
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
    {:ok, canonical} = create_ready_run(bootstrap.session, applied.verification_check)
    {:ok, other_check} = create_required_verification_check(bootstrap.session)

    {:ok, wrong_set_packet} =
      create_packet_with_sources_and_checks(
        bootstrap.session,
        "wrong-check-set",
        [applied.verification_check.graph_item_id, other_check.graph_item_id],
        [other_check.id]
      )

    {:ok, wrong_set_run} =
      start_run_for_packet_version(bootstrap.session, wrong_set_packet.version, "wrong-check-set")

    {:ok, superset_packet} =
      create_packet_with_sources_and_checks(
        bootstrap.session,
        "superset-check-set",
        [applied.verification_check.graph_item_id, other_check.graph_item_id],
        [applied.verification_check.id, other_check.id]
      )

    {:ok, superset_run} =
      start_run_for_packet_version(
        bootstrap.session,
        superset_packet.version,
        "superset-check-set"
      )

    assert {:ok, base} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert base.relationship_summary == %{
             graph_links: 6,
             graph_relationships: 3,
             has_more: false
           }

    base_link_ids = Enum.map(base.graph_links, &"#{&1.type}:#{&1.id}")
    assert "work_packet:#{canonical.packet_version.work_packet_id}" in base_link_ids
    assert "work_run:#{canonical.run.id}" in base_link_ids
    refute "work_packet:#{wrong_set_packet.version.work_packet_id}" in base_link_ids
    refute "work_run:#{wrong_set_run.run.id}" in base_link_ids
    refute "work_packet:#{superset_packet.version.work_packet_id}" in base_link_ids
    refute "work_run:#{superset_run.run.id}" in base_link_ids

    assert {:ok, page} =
             Projections.operator_relationship_details_page(
               bootstrap.session,
               intake.normalized_event.id,
               limit: 20,
               after_cursor: nil
             )

    ids = Enum.map(page.edges, & &1.node.stable_id)
    assert "work_packet:#{canonical.packet_version.work_packet_id}" in ids
    assert "work_run:#{canonical.run.id}" in ids
    refute "work_packet:#{wrong_set_packet.version.work_packet_id}" in ids
    refute "work_run:#{wrong_set_run.run.id}" in ids
    refute "work_packet:#{superset_packet.version.work_packet_id}" in ids
    refute "work_run:#{superset_run.run.id}" in ids

    detail_link_ids =
      page.edges
      |> Enum.filter(&(&1.node.kind == "graph_link"))
      |> Enum.map(& &1.node.stable_id)

    assert Enum.sort(detail_link_ids) == Enum.sort(base_link_ids)
    assert page.graph_link_count == base.relationship_summary.graph_links
    assert page.graph_relationship_count == base.relationship_summary.graph_relationships
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

    {{:ok, workspace}, workspace_queries} =
      QueryCounter.count(fn ->
        Projections.packet_workspace(bootstrap.session, packet_result.packet.id)
      end)

    run_queries = Enum.filter(workspace_queries, &String.contains?(&1.query || "", ~s("runs")))
    assert length(run_queries) == 1
    assert String.contains?(hd(run_queries).query, "LIMIT")

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

  test "packet workspace disables run start while the current version has an active run" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, packet_result} =
      OperatorCommandFixtures.create_ready_packet(
        bootstrap.session,
        [verification_check],
        %{
          title: "Active run packet",
          objective: "Prevent duplicate active runs.",
          context_summary: "The current version already has a run.",
          requirements: "Keep one active run per packet version.",
          success_criteria: "Run start is unavailable until the run finishes.",
          autonomy_posture: "human_supervised"
        }
      )

    {:ok, operation} = Operations.start_operation(bootstrap.session, :work_run_start, [])

    assert {:ok, _run_result} =
             Runs.start_run(bootstrap.session, operation, packet_result.version, %{
               source_surface: "packet_workspace",
               reason: "Start the current packet version.",
               authority_posture: "human_supervised"
             })

    assert {:ok, workspace} =
             Projections.packet_workspace(bootstrap.session, packet_result.packet.id)

    assert workspace.ready?
    assert workspace.allowed_next_actions == ["create_work_packet_version"]
    assert [_create_version, start_run] = workspace.command_affordances
    assert start_run.identity == "start_work_run"
    assert start_run.state == "disabled"
    assert start_run.reason_codes == ["active_work_run"]
    assert start_run.blocker_reasons == ["active_work_run"]
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

      if run_state.status == "failed" do
        assert is_nil(create_candidate)
        assert run_state.status == "failed"
      else
        assert is_nil(create_candidate)

        assert Enum.any?(
                 run_state.command_affordances,
                 &(&1.identity == "record_execution_observation" and &1.state == "enabled")
               )
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

    assert {:ok, remaining_execution} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    assert remaining_execution.status == "awaiting_evidence"

    assert remaining_execution.allowed_next_actions == [
             "record_execution_observation",
             "waive_verification_check"
           ]

    record_observation =
      Enum.find(
        remaining_execution.command_affordances,
        &(&1.identity == "record_execution_observation")
      )

    assert record_observation.state == "enabled"
    assert %{type: "verification_check", id: second_check.id} in record_observation.target_ids
    refute %{type: "verification_check", id: first_check.id} in record_observation.target_ids

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

  defp create_packet_with_sources_and_checks(session, key, source_ids, check_ids) do
    {:ok, operation} =
      Operations.start_operation(session, :work_packet_create,
        idempotency_key: "work-packet-operation:#{key}"
      )

    WorkPackets.create_packet(session, operation, %{
      title: "Packet #{key}",
      objective: "Exercise canonical packet linking.",
      context_summary: "Packet-link predicate coverage.",
      requirements: "Match sources and exact verification checks.",
      success_criteria: "Only canonical packets are linked.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: source_ids,
      verification_check_ids: check_ids
    })
  end

  defp create_next_packet_version(session, packet_id, current_version, check, index) do
    packet =
      Ash.get!(OfficeGraph.WorkPackets.WorkPacket, packet_id, authorize?: false)

    attrs = %{
      expected_current_version_id: current_version.id,
      title: "Event-wide packet version #{index}",
      objective: "Rank linked runs across every packet version.",
      context_summary: "Event-wide run-rank coverage.",
      requirements: "Keep one bounded event run summary.",
      success_criteria: "The newest run controls status.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [check.graph_item_id],
      verification_check_ids: [check.id]
    }

    command_input = Map.put(attrs, :packet_id, packet.id)

    {:ok, operation} =
      Operations.start_command(
        session,
        :work_packet_version_create,
        "event-wide-packet-version:#{index}:#{System.unique_integer([:positive])}",
        command_input
      )

    WorkPackets.create_version(session, operation, packet, attrs)
  end

  defp mark_run_failed!(run) do
    Repo.query!(
      "UPDATE runs SET state = 'failed', aggregate_state = 'failed', execution_state = 'failed', verification_state = 'failed', inserted_at = now() - interval '1 day' WHERE id = $1",
      [Ecto.UUID.dump!(run.id)]
    )
  end

  defp restore_running_run!(run) do
    Repo.query!(
      "UPDATE runs SET state = $1, aggregate_state = $2, execution_state = $3, verification_state = $4, inserted_at = now() WHERE id = $5",
      [
        run.state,
        run.aggregate_state,
        run.execution_state,
        run.verification_state,
        Ecto.UUID.dump!(run.id)
      ]
    )
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
