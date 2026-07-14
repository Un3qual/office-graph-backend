defmodule OfficeGraph.Projections.OperatorInboxProjectionTest do
  use OfficeGraph.TestSupport.OperatorProjectionSupport

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

    assert Enum.map(detail.graph_relationships, & &1.definition_key) == [
             "generated_from",
             "review_finding_for",
             "requires_check"
           ]

    assert detail.audit_trace.resource_count == 7
    assert detail.revision_trace.resource_count == 7

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

    {:ok, relationship_definition} =
      OfficeGraph.WorkGraph.RelationshipDefinitions.fetch_by_key("depends_on")

    {:ok, relationship_operation} =
      Operations.start_operation(bootstrap.session, :graph_relationship_create)

    Repo.query!(
      """
      INSERT INTO graph_relationships
        (id, definition_id, organization_id, workspace_id, source_item_id, target_item_id,
         lifecycle, asserting_principal_id, operation_id, valid_from, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, 'active', $7, $8, now(), now(), now())
      """,
      [
        Ecto.UUID.dump!(cross_tenant_relationship_id),
        Ecto.UUID.dump!(relationship_definition.id),
        Ecto.UUID.dump!(bootstrap.organization.id),
        Ecto.UUID.dump!(bootstrap.workspace.id),
        Ecto.UUID.dump!(applied.signal.graph_item_id),
        Ecto.UUID.dump!(other_check.graph_item_id),
        Ecto.UUID.dump!(bootstrap.principal.id),
        Ecto.UUID.dump!(relationship_operation.id)
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
end
