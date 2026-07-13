defmodule OfficeGraph.Projections.OperatorPacketProjectionTest do
  use OfficeGraph.TestSupport.OperatorProjectionSupport

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

    assert {:ok, run_result} =
             Runs.start_run(bootstrap.session, operation, packet_result.version, %{
               source_surface: "packet_workspace",
               reason: "Start the current packet version.",
               authority_posture: "human_supervised"
             })

    Repo.query!(
      "UPDATE runs SET aggregate_state = NULL, verification_state = NULL WHERE id = $1",
      [Ecto.UUID.dump!(run_result.run.id)]
    )

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
end
