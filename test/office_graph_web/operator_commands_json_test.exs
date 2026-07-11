defmodule OfficeGraphWeb.OperatorCommandsJsonTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.ProposedChanges.ProposedGraphChange

  import OfficeGraph.SessionCaseHelpers

  describe "manual intake and proposal application commands" do
    test "execute one durable step and replay stable JSON results", %{conn: conn} do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      conn = Ash.PlugHelpers.set_actor(conn, bootstrap.session)

      intake_input = %{
        idempotency_key: unique_key("intake"),
        source_identity: "manual:json-command",
        replay_identity: unique_key("paste"),
        body: "Advance the operator loop through JSON commands."
      }

      intake = command(conn, "submit-manual-intake", intake_input)
      assert intake["command"] == "submit_manual_intake"
      assert is_binary(intake["operation_id"])
      assert is_binary(intake["result"]["normalized_event_id"])
      assert [_first | _rest] = intake["result"]["proposed_change_ids"]
      assert command(conn, "submit-manual-intake", intake_input) == intake

      apply_input = %{
        idempotency_key: unique_key("apply"),
        normalized_event_id: intake["result"]["normalized_event_id"],
        proposed_change_ids: intake["result"]["proposed_change_ids"]
      }

      applied = command(conn, "apply-proposed-changes", apply_input)
      assert applied["command"] == "apply_proposed_changes"
      assert is_binary(applied["operation_id"])
      assert is_binary(applied["result"]["signal"]["id"])
      assert is_binary(applied["result"]["task"]["id"])
      assert is_binary(applied["result"]["review_finding"]["id"])
      assert is_binary(applied["result"]["verification_check"]["id"])
      assert is_binary(applied["result"]["verification_check"]["graph_item_id"])
      assert command(conn, "apply-proposed-changes", apply_input) == applied

      affected_types = MapSet.new(applied["affected_ids"], & &1["type"])

      assert MapSet.subset?(
               MapSet.new([
                 "signal",
                 "task",
                 "review_finding",
                 "verification_check",
                 "proposed_graph_change"
               ]),
               affected_types
             )
    end

    test "return safe field, authorization, idempotency, and stale-state errors", %{conn: conn} do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      owner_conn = Ash.PlugHelpers.set_actor(conn, bootstrap.session)

      invalid = raw_command(owner_conn, "submit-manual-intake", %{idempotency_key: "missing"})
      assert invalid.status == 422

      assert %{
               "command" => "submit_manual_intake",
               "error" => %{
                 "code" => "validation_failed",
                 "field" => "source_identity"
               }
             } = json_response(invalid, 422)

      no_capabilities =
        create_session_with_capabilities!(bootstrap, [], prefix: "json-command-forbidden")

      forbidden =
        conn
        |> Ash.PlugHelpers.set_actor(no_capabilities)
        |> raw_command("submit-manual-intake", %{
          idempotency_key: unique_key("forbidden"),
          source_identity: "manual:forbidden-json-command",
          replay_identity: unique_key("forbidden-replay"),
          body: "This command is not authorized."
        })

      assert forbidden.status == 403

      assert %{
               "command" => "submit_manual_intake",
               "error" => %{"code" => "forbidden"}
             } = json_response(forbidden, 403)

      intake_input = %{
        idempotency_key: unique_key("conflict"),
        source_identity: "manual:json-conflict",
        replay_identity: unique_key("conflict-replay"),
        body: "Original command body."
      }

      _intake = command(owner_conn, "submit-manual-intake", intake_input)

      conflict =
        raw_command(
          owner_conn,
          "submit-manual-intake",
          Map.put(intake_input, :body, "Changed command body.")
        )

      assert conflict.status == 409

      assert %{
               "command" => "submit_manual_intake",
               "error" => %{"code" => "idempotency_conflict"}
             } = json_response(conflict, 409)

      intake =
        command(owner_conn, "submit-manual-intake", %{
          idempotency_key: unique_key("stale-intake"),
          source_identity: "manual:json-stale",
          replay_identity: unique_key("stale-replay"),
          body: "Create a proposal set for a stale retry."
        })

      apply_input = %{
        idempotency_key: unique_key("first-apply"),
        normalized_event_id: intake["result"]["normalized_event_id"],
        proposed_change_ids: intake["result"]["proposed_change_ids"]
      }

      _applied = command(owner_conn, "apply-proposed-changes", apply_input)

      stale =
        raw_command(
          owner_conn,
          "apply-proposed-changes",
          Map.put(apply_input, :idempotency_key, unique_key("stale-apply"))
        )

      assert stale.status == 409

      assert %{
               "command" => "apply_proposed_changes",
               "error" => %{"code" => "invalid_proposed_change_status"}
             } = json_response(stale, 409)

      assert Enum.all?(intake["result"]["proposed_change_ids"], fn id ->
               Ash.get!(ProposedGraphChange, id, authorize?: false).status == "applied"
             end)
    end
  end

  describe "packet, packet-version, and run-start commands" do
    test "preserve immutable versioning, replay, and ordered required checks", %{conn: conn} do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      conn = Ash.PlugHelpers.set_actor(conn, bootstrap.session)
      applied = create_applied_workflow(conn, "packet-sequence")
      check = applied["result"]["verification_check"]

      packet_input = %{
        idempotency_key: unique_key("packet"),
        title: "JSON command packet",
        objective: "Exercise the packet and run JSON commands.",
        context_summary: "The selected proposal is ready for packet preparation.",
        requirements: "Preserve immutable packet versions.",
        success_criteria: "A packet-backed run starts with its required check.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: [check["graph_item_id"]],
        verification_check_ids: [check["id"]]
      }

      packet = command(conn, "create-work-packet", packet_input)
      assert packet["command"] == "create_work_packet"

      assert packet["result"]["packet"]["current_version_id"] ==
               packet["result"]["packet_version"]["id"]

      assert packet["result"]["packet_version"]["version_number"] == 1
      assert command(conn, "create-work-packet", packet_input) == packet

      version_input =
        packet_input
        |> Map.merge(%{
          idempotency_key: unique_key("packet-version"),
          packet_id: packet["result"]["packet"]["id"],
          expected_current_version_id: packet["result"]["packet_version"]["id"],
          title: "Versioned JSON command packet"
        })

      version = command(conn, "create-work-packet-version", version_input)
      assert version["command"] == "create_work_packet_version"
      assert version["result"]["packet_version"]["version_number"] == 2

      assert version["result"]["packet"]["current_version_id"] ==
               version["result"]["packet_version"]["id"]

      assert command(conn, "create-work-packet-version", version_input) == version

      run_input = %{
        idempotency_key: unique_key("run"),
        packet_version_id: version["result"]["packet_version"]["id"],
        source_surface: "operator_commands_json_test",
        reason: "Verify JSON packet-run command parity.",
        authority_posture: "human_supervised"
      }

      started = command(conn, "start-work-run", run_input)
      assert started["command"] == "start_work_run"
      assert started["result"]["run"]["work_packet_version_id"] == run_input.packet_version_id

      assert [required_check] = started["result"]["required_checks"]
      assert required_check["verification_check_id"] == check["id"]
      assert command(conn, "start-work-run", run_input) == started

      assert MapSet.new(started["affected_ids"], & &1["type"]) ==
               MapSet.new(["work_run", "run_required_check"])
    end

    test "reject a stale packet version without creating another version", %{conn: conn} do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      conn = Ash.PlugHelpers.set_actor(conn, bootstrap.session)
      applied = create_applied_workflow(conn, "stale-version")
      check = applied["result"]["verification_check"]

      packet =
        command(conn, "create-work-packet", %{
          idempotency_key: unique_key("stale-packet"),
          title: "Stale JSON packet",
          objective: "Exercise stale packet version behavior.",
          context_summary: "The packet has an authoritative current version.",
          requirements: "Reject stale expected versions.",
          success_criteria: "Only one new version is committed.",
          autonomy_posture: "fully_autonomous",
          source_graph_item_ids: [check["graph_item_id"]],
          verification_check_ids: [check["id"]]
        })

      base_version_input = %{
        idempotency_key: unique_key("fresh-version"),
        packet_id: packet["result"]["packet"]["id"],
        expected_current_version_id: packet["result"]["packet_version"]["id"],
        title: "Fresh JSON packet version",
        objective: "Exercise stale packet version behavior.",
        context_summary: "The packet has an authoritative current version.",
        requirements: "Reject stale expected versions.",
        success_criteria: "Only one new version is committed.",
        autonomy_posture: "fully_autonomous",
        source_graph_item_ids: [check["graph_item_id"]],
        verification_check_ids: [check["id"]]
      }

      fresh = command(conn, "create-work-packet-version", base_version_input)

      stale =
        raw_command(
          conn,
          "create-work-packet-version",
          Map.put(base_version_input, :idempotency_key, unique_key("stale-version"))
        )

      assert stale.status == 409

      assert %{
               "command" => "create_work_packet_version",
               "error" => %{
                 "code" => "stale_packet_version",
                 "current_version_id" => current_version_id
               }
             } = json_response(stale, 409)

      assert current_version_id == fresh["result"]["packet_version"]["id"]
    end
  end

  describe "observation, evidence, acceptance, and waiver commands" do
    test "match GraphQL command, replay, authorization, and stale-state semantics", %{conn: conn} do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      conn = Ash.PlugHelpers.set_actor(conn, bootstrap.session)
      first = create_applied_workflow(conn, "verification-first")["result"]["verification_check"]

      second =
        create_applied_workflow(conn, "verification-second")["result"]["verification_check"]

      started = create_started_run(conn, "verification", [first, second])

      observation_input = %{
        idempotency_key: unique_key("observation-operation"),
        run_id: started["result"]["run"]["id"],
        verification_check_id: first["id"],
        source_graph_item_id: first["graph_item_id"],
        observation_source_kind: "human",
        observation_source_identity: "manual:json-observation",
        observation_idempotency_key: unique_key("observation-source"),
        observed_status: "passed",
        normalized_status: "succeeded",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        observation_rationale: "The first JSON command check passed."
      }

      observed = command(conn, "record-execution-observation", observation_input)
      assert observed["command"] == "record_execution_observation"
      assert observed["result"]["observation"]["normalized_status"] == "succeeded"
      assert command(conn, "record-execution-observation", observation_input) == observed

      candidate_input = %{
        idempotency_key: unique_key("candidate"),
        work_run_id: started["result"]["run"]["id"],
        verification_check_id: first["id"],
        execution_observation_id: observed["result"]["observation"]["id"],
        claim: "The first JSON command check has passing evidence.",
        source_kind: "human",
        source_identity: "manual:json-evidence",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        sensitivity: "internal"
      }

      candidate = command(conn, "create-evidence-candidate", candidate_input)
      assert candidate["command"] == "create_evidence_candidate"
      assert candidate["result"]["evidence_candidate"]["candidate_state"] == "candidate"
      assert command(conn, "create-evidence-candidate", candidate_input) == candidate

      accept_input = %{
        idempotency_key: unique_key("accept"),
        evidence_candidate_id: candidate["result"]["evidence_candidate"]["id"],
        title: "Accepted JSON command evidence",
        body: "The first required check passed.",
        result: "passed",
        acceptance_policy_basis: "owner_acceptance"
      }

      accepted = command(conn, "accept-evidence", accept_input)
      assert accepted["command"] == "accept_evidence"
      assert accepted["result"]["evidence_item"]["state"] == "accepted"
      assert accepted["result"]["verification_result"]["result"] == "passed"
      assert command(conn, "accept-evidence", accept_input) == accepted

      assert MapSet.subset?(
               MapSet.new([
                 "evidence_candidate",
                 "evidence_item",
                 "verification_result",
                 "verification_check",
                 "run_required_check",
                 "review_finding",
                 "task",
                 "work_run"
               ]),
               MapSet.new(accepted["affected_ids"], & &1["type"])
             )

      second_required_check =
        Enum.find(
          started["result"]["required_checks"],
          &(&1["verification_check_id"] == second["id"])
        )

      waiver_input = %{
        idempotency_key: unique_key("waive"),
        run_id: accepted["result"]["run"]["id"],
        run_required_check_id: second_required_check["id"],
        expected_execution_state: accepted["result"]["run"]["execution_state"],
        expected_verification_state: accepted["result"]["run"]["verification_state"],
        reason: "The second check is governed by an approved exception.",
        policy_basis: "owner_exception"
      }

      stale =
        raw_command(
          conn,
          "waive-verification-check",
          waiver_input
          |> Map.put(:idempotency_key, unique_key("stale-waive"))
          |> Map.put(:expected_execution_state, "queued")
        )

      assert stale.status == 409

      assert %{
               "command" => "waive_verification_check",
               "error" => %{"code" => "stale_run_state"}
             } = json_response(stale, 409)

      no_capabilities =
        create_session_with_capabilities!(bootstrap, [], prefix: "json-waive-forbidden")

      forbidden =
        conn
        |> Ash.PlugHelpers.set_actor(no_capabilities)
        |> raw_command(
          "waive-verification-check",
          Map.put(waiver_input, :idempotency_key, unique_key("forbidden-waive"))
        )

      assert forbidden.status == 403

      assert %{
               "command" => "waive_verification_check",
               "error" => %{"code" => "forbidden"}
             } = json_response(forbidden, 403)

      waived = command(conn, "waive-verification-check", waiver_input)
      assert waived["command"] == "waive_verification_check"
      assert waived["result"]["required_check"]["state"] == "waived"
      assert waived["result"]["verification_result"]["result"] == "waived"
      assert waived["result"]["run"]["verification_state"] == "verified"
      assert command(conn, "waive-verification-check", waiver_input) == waived
    end
  end

  defp command(conn, command, input) do
    conn
    |> raw_command(command, input)
    |> json_response(200)
  end

  defp raw_command(conn, command, input) do
    post(conn, "/api/v1/commands/#{command}", input)
  end

  defp create_applied_workflow(conn, label) do
    intake =
      command(conn, "submit-manual-intake", %{
        idempotency_key: unique_key("#{label}-intake"),
        source_identity: "manual:#{label}",
        replay_identity: unique_key("#{label}-replay"),
        body: "Create the #{label} proposal set."
      })

    command(conn, "apply-proposed-changes", %{
      idempotency_key: unique_key("#{label}-apply"),
      normalized_event_id: intake["result"]["normalized_event_id"],
      proposed_change_ids: intake["result"]["proposed_change_ids"]
    })
  end

  defp create_started_run(conn, label, checks) do
    packet =
      command(conn, "create-work-packet", %{
        idempotency_key: unique_key("#{label}-packet"),
        title: "#{label} JSON packet",
        objective: "Advance verification commands through the JSON API.",
        context_summary: "The selected checks are ready for execution.",
        requirements: "Preserve command replay and authorization behavior.",
        success_criteria: "All required checks are accepted or waived.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: Enum.map(checks, & &1["graph_item_id"]),
        verification_check_ids: Enum.map(checks, & &1["id"])
      })

    command(conn, "start-work-run", %{
      idempotency_key: unique_key("#{label}-run"),
      packet_version_id: packet["result"]["packet_version"]["id"],
      source_surface: "operator_commands_json_test",
      reason: "Exercise verification JSON commands.",
      authority_posture: "human_supervised"
    })
  end

  defp unique_key(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end
end
