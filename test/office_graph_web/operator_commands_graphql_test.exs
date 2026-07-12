defmodule OfficeGraphWeb.OperatorCommandsGraphQLTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Audit.AuditRecord
  alias OfficeGraph.Content.{Document, DocumentBlock, DocumentRevision}
  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations.{ExternalSource, NormalizedIntakeEvent, RawArchive}
  alias OfficeGraph.OperatorCommandFixtures
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Repo
  alias OfficeGraph.Revisions.Revision
  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

  alias OfficeGraph.WorkGraph.{
    EvidenceCandidate,
    EvidenceItem,
    GraphItem,
    GraphRelationship,
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck,
    VerificationResult
  }

  alias OfficeGraph.WorkPackets.{
    WorkPacket,
    WorkPacketRequiredCheck,
    WorkPacketSourceReference,
    WorkPacketVersion
  }

  @command_record_families [
    AuditRecord,
    Document,
    DocumentBlock,
    DocumentRevision,
    ExternalSource,
    RawArchive,
    NormalizedIntakeEvent,
    ProposedGraphChange,
    GraphItem,
    GraphRelationship,
    Signal,
    Task,
    ReviewFinding,
    VerificationCheck,
    WorkPacket,
    WorkPacketVersion,
    WorkPacketSourceReference,
    WorkPacketRequiredCheck,
    Run,
    RunRequiredCheck,
    ExecutionObservation,
    EvidenceCandidate,
    EvidenceItem,
    VerificationResult,
    Revision
  ]

  require Ash.Query

  import OfficeGraph.SessionCaseHelpers

  test "manual intake is a server-owned idempotent GraphQL command", %{conn: conn} do
    input = %{
      idempotencyKey: "graphql-manual-intake",
      sourceIdentity: "manual:graphql-command",
      replayIdentity: "paste:graphql-command",
      body: "Investigate the GraphQL operator command loop."
    }

    mutation = """
    mutation Submit($input: SubmitManualIntakeInput!) {
      submitManualIntake(input: $input) {
        command
        operationId
        normalizedEventId
        proposedChangeIds
        affectedIds { type id }
      }
    }
    """

    first = graphql(conn, mutation, %{input: input})
    replay = graphql(conn, mutation, %{input: input})

    assert first["command"] == "submit_manual_intake"
    assert is_binary(first["operationId"])
    assert is_binary(first["normalizedEventId"])
    assert length(first["proposedChangeIds"]) == 4
    assert replay == first

    conflict =
      raw_graphql(conn, mutation, %{
        input: %{input | body: "Changed command input."}
      })

    assert [%{"extensions" => %{"code" => "idempotency_conflict"}}] = conflict["errors"]
  end

  test "manual intake preserves leading and trailing body whitespace", %{conn: conn} do
    body = "\n  pasted log line  \n"

    result =
      graphql(
        conn,
        """
        mutation Submit($input: SubmitManualIntakeInput!) {
          submitManualIntake(input: $input) { operationId }
        }
        """,
        %{
          input: %{
            idempotencyKey: "graphql-manual-whitespace",
            sourceIdentity: "manual:graphql-whitespace",
            replayIdentity: "paste:graphql-whitespace",
            body: body
          }
        }
      )

    archive =
      RawArchive
      |> Ash.Query.filter(operation_id == ^result["operationId"])
      |> Ash.read_one!(authorize?: false)

    assert archive.body == body
  end

  test "proposal application rejects a mismatched normalized event target", %{conn: conn} do
    first =
      command(conn, :submit_manual_intake, %{
        idempotencyKey: unique_key("mismatch-first"),
        sourceIdentity: "manual:mismatch-first",
        replayIdentity: unique_key("mismatch-first-replay"),
        body: "Create the first proposal set."
      })

    second =
      command(conn, :submit_manual_intake, %{
        idempotencyKey: unique_key("mismatch-second"),
        sourceIdentity: "manual:mismatch-second",
        replayIdentity: unique_key("mismatch-second-replay"),
        body: "Create the second proposal set."
      })

    before_snapshot = command_record_snapshot()

    response =
      raw_command(conn, :apply_proposed_changes, %{
        idempotencyKey: unique_key("mismatch-apply"),
        normalizedEventId: second["normalizedEventId"],
        proposedChangeIds: first["proposedChangeIds"]
      })

    assert [%{"extensions" => %{"code" => "invalid_proposed_change_set"}}] =
             response["errors"]

    assert command_record_snapshot() == before_snapshot
  end

  test "proposal replay corruption returns a safe JSON-encodable error", %{conn: conn} do
    intake =
      command(conn, :submit_manual_intake, %{
        idempotencyKey: unique_key("corrupt-replay-intake"),
        sourceIdentity: "manual:corrupt-replay",
        replayIdentity: unique_key("corrupt-replay-source"),
        body: "Create a proposal result that will be corrupted."
      })

    apply_input = %{
      idempotencyKey: unique_key("corrupt-replay-apply"),
      normalizedEventId: intake["normalizedEventId"],
      proposedChangeIds: intake["proposedChangeIds"]
    }

    applied = command(conn, :apply_proposed_changes, apply_input)

    assert %{num_rows: 1} =
             Repo.query!(
               "DELETE FROM verification_checks WHERE id = $1::uuid",
               [Ecto.UUID.dump!(applied["verificationCheck"]["id"])]
             )

    response = raw_command(conn, :apply_proposed_changes, apply_input)

    assert [%{"extensions" => %{"code" => "invalid_proposed_change_replay"}}] =
             response["errors"]

    assert {:ok, _json} = Jason.encode(response)
    refute inspect(response["errors"]) =~ "OfficeGraph."
  end

  test "command rollback snapshots detect in-place state updates without row-count changes" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, check} = create_required_verification_check(bootstrap.session, "snapshot-state")
    before_snapshot = command_record_snapshot()

    check
    |> Ash.Changeset.for_update(:mark_satisfied, %{})
    |> Ash.update!(authorize?: false)

    refute command_record_snapshot() == before_snapshot
  end

  test "GraphQL exposes only step-specific operator workflow commands", %{conn: conn} do
    response =
      raw_graphql(
        conn,
        """
        query OperatorCommandSurface {
          __schema {
            mutationType {
              fields { name }
            }
          }
        }
        """,
        %{}
      )

    mutation_names =
      response
      |> get_in(["data", "__schema", "mutationType", "fields"])
      |> Enum.map(& &1["name"])

    retired_mutation = Enum.join(["execute", "Packet", "Run", "Verification"])
    refute retired_mutation in mutation_names
  end

  test "step-specific GraphQL commands complete the operator loop and replay safely", %{
    conn: conn
  } do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, second_check} = create_required_verification_check(bootstrap.session, "second")

    intake_input = %{
      idempotencyKey: unique_key("intake"),
      sourceIdentity: "manual:graphql-sequence",
      replayIdentity: unique_key("paste"),
      body: "Complete the step-specific GraphQL command sequence."
    }

    intake = command(conn, :submit_manual_intake, intake_input)
    assert_payload(intake, "submit_manual_intake", ["normalized_intake_event"])

    apply_input = %{
      idempotencyKey: unique_key("apply"),
      normalizedEventId: " #{intake["normalizedEventId"]} ",
      proposedChangeIds: Enum.map(intake["proposedChangeIds"], &" #{&1} ")
    }

    applied = command(conn, :apply_proposed_changes, apply_input)

    assert_payload(applied, "apply_proposed_changes", [
      "signal",
      "task",
      "review_finding",
      "verification_check",
      "proposed_graph_change"
    ])

    assert MapSet.new(
             for %{"type" => "proposed_graph_change", "id" => id} <- applied["affectedIds"],
                 do: id
           ) == MapSet.new(intake["proposedChangeIds"])

    first_check = applied["verificationCheck"]
    source_ids = [first_check["graphItemId"], second_check.graph_item_id]
    verification_check_ids = [first_check["id"], second_check.id]

    packet_input = packet_input(unique_key("packet"), source_ids, verification_check_ids)
    packet = command(conn, :create_work_packet, packet_input)
    assert_payload(packet, "create_work_packet", ["work_packet", "work_packet_version"])

    version_input =
      packet_input(unique_key("version"), source_ids, verification_check_ids)
      |> Map.merge(%{
        packetId: packet["packet"]["id"],
        expectedCurrentVersionId: packet["packetVersion"]["id"],
        title: "Versioned GraphQL command packet"
      })

    version = command(conn, :create_work_packet_version, version_input)
    assert_payload(version, "create_work_packet_version", ["work_packet", "work_packet_version"])

    before_stale_version = command_record_snapshot()

    stale_version =
      raw_command(
        conn,
        :create_work_packet_version,
        version_input
        |> Map.put(:idempotencyKey, unique_key("stale-version"))
        |> Map.put(:expectedCurrentVersionId, packet["packetVersion"]["id"])
      )

    assert [%{"extensions" => %{"code" => "stale_packet_version"}}] = stale_version["errors"]
    assert command_record_snapshot() == before_stale_version

    run_input = %{
      idempotencyKey: unique_key("run"),
      packetVersionId: version["packetVersion"]["id"],
      sourceSurface: "operator_commands_graphql_test",
      reason: "Exercise each step-specific command.",
      authorityPosture: "human_supervised"
    }

    stale_run =
      raw_command(
        conn,
        :start_work_run,
        run_input
        |> Map.put(:idempotencyKey, unique_key("stale-run"))
        |> Map.put(:packetVersionId, packet["packetVersion"]["id"])
      )

    assert [%{"extensions" => %{"code" => "stale_packet_version"}}] = stale_run["errors"]

    started = command(conn, :start_work_run, run_input)
    assert_payload(started, "start_work_run", ["work_run", "run_required_check"])

    duplicate_run =
      raw_command(
        conn,
        :start_work_run,
        Map.put(run_input, :idempotencyKey, unique_key("active-run"))
      )

    assert [%{"extensions" => %{"code" => "active_work_run"}}] = duplicate_run["errors"]

    first_required_check =
      Enum.find(started["requiredChecks"], &(&1["verificationCheckId"] == first_check["id"]))

    second_required_check =
      Enum.find(started["requiredChecks"], &(&1["verificationCheckId"] == second_check.id))

    observation_input = %{
      idempotencyKey: unique_key("observation-operation"),
      runId: started["run"]["id"],
      verificationCheckId: first_check["id"],
      sourceGraphItemId: first_check["graphItemId"],
      observationSourceKind: "human",
      observationSourceIdentity: "manual:graphql-sequence-observation",
      observationIdempotencyKey: unique_key("observation-source"),
      observedStatus: "passed",
      normalizedStatus: "succeeded",
      freshnessState: "fresh",
      trustBasis: "owner_attested",
      observationRationale: "The first required check passed."
    }

    observed = command(conn, :record_execution_observation, observation_input)

    assert_payload(observed, "record_execution_observation", ["execution_observation", "work_run"])

    candidate_input = %{
      idempotencyKey: unique_key("candidate"),
      workRunId: observed["run"]["id"],
      verificationCheckId: first_check["id"],
      executionObservationId: observed["observation"]["id"],
      claim: "The first required check has passing evidence.",
      sourceKind: "human",
      sourceIdentity: "manual:graphql-sequence-evidence",
      freshnessState: "fresh",
      trustBasis: "owner_attested",
      sensitivity: "internal"
    }

    candidate = command(conn, :create_evidence_candidate, candidate_input)
    assert_payload(candidate, "create_evidence_candidate", ["evidence_candidate"])

    accept_input = %{
      idempotencyKey: unique_key("accept"),
      evidenceCandidateId: candidate["evidenceCandidate"]["id"],
      title: "Accepted GraphQL command evidence",
      body: "The first required check passed.",
      result: "passed",
      acceptancePolicyBasis: "owner_acceptance"
    }

    accepted = command(conn, :accept_evidence, accept_input)

    assert_payload(accepted, "accept_evidence", [
      "evidence_candidate",
      "evidence_item",
      "verification_result",
      "verification_check",
      "run_required_check",
      "work_run",
      "review_finding",
      "task"
    ])

    assert %{"type" => "review_finding", "id" => applied["reviewFinding"]["id"]} in accepted[
             "affectedIds"
           ]

    assert %{"type" => "task", "id" => applied["task"]["id"]} in accepted["affectedIds"]

    accepted_required_check =
      Ash.get!(RunRequiredCheck, first_required_check["id"], authorize?: false)

    assert accepted_required_check.state == "satisfied"

    before_stale_waiver = command_record_snapshot()

    stale_waiver =
      raw_command(conn, :waive_verification_check, %{
        idempotencyKey: unique_key("stale-waive"),
        runId: accepted["run"]["id"],
        runRequiredCheckId: second_required_check["id"],
        expectedExecutionState: "queued",
        expectedVerificationState: accepted["run"]["verificationState"],
        reason: "This stale request must not waive the check.",
        policyBasis: "owner_exception"
      })

    assert [%{"extensions" => %{"code" => "stale_run_state"}}] = stale_waiver["errors"]
    assert command_record_snapshot() == before_stale_waiver

    waiver_input = %{
      idempotencyKey: unique_key("waive"),
      runId: accepted["run"]["id"],
      runRequiredCheckId: second_required_check["id"],
      expectedExecutionState: accepted["run"]["executionState"],
      expectedVerificationState: accepted["run"]["verificationState"],
      reason: "The second check is governed by an approved exception.",
      policyBasis: "owner_exception"
    }

    waived = command(conn, :waive_verification_check, waiver_input)

    assert_payload(waived, "waive_verification_check", [
      "verification_result",
      "run_required_check",
      "work_run"
    ])

    assert waived["requiredCheck"]["id"] == second_required_check["id"]
    assert waived["requiredCheck"]["state"] == "waived"
    assert waived["run"]["verificationState"] == "verified"

    commands = [
      {:submit_manual_intake, intake_input, intake, :body, "Changed intake body."},
      {:apply_proposed_changes, apply_input, applied, :proposedChangeIds,
       Enum.reverse(apply_input.proposedChangeIds)},
      {:create_work_packet, packet_input, packet, :title, "Changed packet title"},
      {:create_work_packet_version, version_input, version, :sourceGraphItemIds,
       Enum.reverse(source_ids)},
      {:start_work_run, run_input, started, :reason, "Changed run reason."},
      {:record_execution_observation, observation_input, observed, :observationRationale,
       "Changed rationale."},
      {:create_evidence_candidate, candidate_input, candidate, :claim, "Changed claim."},
      {:accept_evidence, accept_input, accepted, :title, "Changed evidence title"},
      {:waive_verification_check, waiver_input, waived, :reason, "Changed waiver reason."}
    ]

    before_retry_snapshot = command_record_snapshot()

    Enum.each(commands, fn {name, input, expected, changed_field, changed_value} ->
      assert stable_payload(command(conn, name, input)) == stable_payload(expected)

      response = raw_command(conn, name, Map.put(input, changed_field, changed_value))
      assert [%{"extensions" => %{"code" => "idempotency_conflict"}}] = response["errors"]
    end)

    assert command_record_snapshot() == before_retry_snapshot
  end

  test "runless evidence acceptance returns a successful payload without a run", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session, "runless")

    review_finding =
      Ash.get!(ReviewFinding, verification_check.review_finding_id, authorize?: false)

    {:ok, candidate_operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: unique_key("runless-candidate")
      )

    {:ok, candidate} =
      Verification.create_evidence_candidate(bootstrap.session, candidate_operation, %{
        verification_check_id: verification_check.id,
        claim: "Runless GraphQL evidence candidate.",
        source_kind: "human_note",
        source_identity: "manual:runless-graphql-candidate",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        sensitivity: "internal"
      })

    accepted =
      command(conn, :accept_evidence, %{
        idempotencyKey: unique_key("runless-accept"),
        evidenceCandidateId: candidate.id,
        title: "Runless accepted GraphQL evidence",
        body: "This evidence is not attached to a work run.",
        result: "passed",
        acceptancePolicyBasis: "owner_acceptance"
      })

    assert accepted["run"] == nil
    refute Enum.any?(accepted["affectedIds"], &(&1["type"] == "work_run"))
    assert Enum.any?(accepted["affectedIds"], &(&1["type"] == "verification_check"))

    assert %{"type" => "review_finding", "id" => review_finding.id} in accepted["affectedIds"]

    assert %{"type" => "task", "id" => review_finding.task_id} in accepted["affectedIds"]

    verification_result =
      Ash.get!(VerificationResult, accepted["verificationResult"]["id"], authorize?: false)

    assert verification_result.reason == nil
    assert verification_result.policy_basis == "owner_acceptance"
  end

  test "run-start-only sessions can target packet versions without skeleton read", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session, "run-only")
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    run_only =
      create_session_with_capabilities!(bootstrap, ["work_run.start"], prefix: "graphql-run-only")

    started =
      conn
      |> Ash.PlugHelpers.set_actor(run_only)
      |> command(:start_work_run, %{
        idempotencyKey: unique_key("run-only"),
        packetVersionId: packet_result.version.id,
        sourceSurface: "operator_commands_graphql_test",
        reason: "Prove least-capability run creation.",
        authorityPosture: "human_supervised"
      })

    assert started["run"]["id"]
  end

  test "observation-only sessions can target runs without skeleton read", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, verification_check} =
      create_required_verification_check(bootstrap.session, "observe-only")

    {:ok, run_result} = create_ready_run(bootstrap.session, [verification_check])

    observation_only =
      create_session_with_capabilities!(bootstrap, ["execution_observation.record"],
        prefix: "graphql-observation-only"
      )

    observed =
      conn
      |> Ash.PlugHelpers.set_actor(observation_only)
      |> command(:record_execution_observation, %{
        idempotencyKey: unique_key("observation-only-operation"),
        runId: run_result.run.id,
        verificationCheckId: verification_check.id,
        sourceGraphItemId: verification_check.graph_item_id,
        observationSourceKind: "human",
        observationSourceIdentity: "manual:observation-only",
        observationIdempotencyKey: unique_key("observation-only-source"),
        observedStatus: "passed",
        normalizedStatus: "succeeded",
        freshnessState: "fresh",
        trustBasis: "owner_attested",
        observationRationale: "Prove least-capability observation recording."
      })

    assert observed["run"]["id"] == run_result.run.id
  end

  test "accept-only sessions can target candidates and report every changed check", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, verification_check} =
      create_required_verification_check(bootstrap.session, "accept-only")

    {:ok, run_result} = create_ready_run(bootstrap.session, [verification_check])

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check)

    {:ok, candidate} =
      create_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation
      )

    accept_only =
      create_session_with_capabilities!(bootstrap, ["evidence.accept"],
        prefix: "graphql-accept-only"
      )

    accepted =
      conn
      |> Ash.PlugHelpers.set_actor(accept_only)
      |> command(:accept_evidence, %{
        idempotencyKey: unique_key("accept-only"),
        evidenceCandidateId: candidate.id,
        title: "Accepted by a least-capability operator",
        body: "The required check passed.",
        result: "passed",
        acceptancePolicyBasis: "owner_acceptance"
      })

    assert_payload(accepted, "accept_evidence", [
      "evidence_candidate",
      "evidence_item",
      "verification_result",
      "verification_check",
      "run_required_check",
      "work_run"
    ])
  end

  test "waive-only sessions can target runs and required checks without skeleton read", %{
    conn: conn
  } do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, verification_check} =
      create_required_verification_check(bootstrap.session, "waive-only")

    {:ok, run_result} = create_ready_run(bootstrap.session, [verification_check])
    [required_check] = run_result.required_checks

    waive_only =
      create_session_with_capabilities!(bootstrap, ["verification.waive"],
        prefix: "graphql-waive-only"
      )

    waived =
      conn
      |> Ash.PlugHelpers.set_actor(waive_only)
      |> command(:waive_verification_check, %{
        idempotencyKey: unique_key("waive-only"),
        runId: run_result.run.id,
        runRequiredCheckId: required_check.id,
        expectedExecutionState: run_result.run.execution_state,
        expectedVerificationState: run_result.run.verification_state,
        reason: "Approved least-capability exception.",
        policyBasis: "owner_exception"
      })

    assert waived["requiredCheck"]["state"] == "waived"
  end

  test "apply commands without read or apply grants return a safe forbidden error", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    intake =
      command(conn, :submit_manual_intake, %{
        idempotencyKey: unique_key("no-cap-intake"),
        sourceIdentity: "manual:no-cap-apply",
        replayIdentity: unique_key("no-cap-replay"),
        body: "Prove safe apply authorization errors."
      })

    no_capabilities =
      create_session_with_capabilities!(bootstrap, [], prefix: "graphql-no-capabilities")

    response =
      conn
      |> Ash.PlugHelpers.set_actor(no_capabilities)
      |> raw_command(:apply_proposed_changes, %{
        idempotencyKey: unique_key("no-cap-apply"),
        normalizedEventId: intake["normalizedEventId"],
        proposedChangeIds: intake["proposedChangeIds"]
      })

    assert [%{"extensions" => %{"code" => "forbidden"}}] = response["errors"]
  end

  test "version-only sessions can create a packet version without skeleton read", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, verification_check} =
      create_required_verification_check(bootstrap.session, "version-only")

    {:ok, packet_operation} = Operations.start_operation(bootstrap.session, :work_packet_create)

    {:ok, packet_result} =
      WorkPackets.create_packet(bootstrap.session, packet_operation, %{
        title: "Version-only command packet",
        objective: "Prove least-capability version creation.",
        context_summary: "The packet already exists in the operator workspace.",
        requirements: "Create the next version without skeleton.read.",
        success_criteria: "The command returns the new packet version.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: [verification_check.graph_item_id],
        verification_check_ids: [verification_check.id]
      })

    version_only =
      create_session_with_capabilities!(bootstrap, ["work_packet.version.create"],
        prefix: "graphql-version-only"
      )

    input =
      packet_input(
        unique_key("version-only-command"),
        [verification_check.graph_item_id],
        [verification_check.id]
      )
      |> Map.merge(%{
        packetId: packet_result.packet.id,
        expectedCurrentVersionId: packet_result.version.id,
        title: "Version-only command packet v2"
      })

    created =
      conn
      |> Ash.PlugHelpers.set_actor(version_only)
      |> command(:create_work_packet_version, input)

    assert created["packet"]["id"] == packet_result.packet.id
    assert created["packetVersion"]["versionNumber"] == 2
  end

  test "every command rejects missing input and forbidden sessions without partial writes", %{
    conn: conn
  } do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, check} = create_required_verification_check(bootstrap.session, "guardrails")

    seed = seed_command_targets(conn, check)
    before_snapshot = command_record_snapshot()

    Enum.each(seed.command_inputs, fn {name, input, required_field} ->
      missing = raw_command(conn, name, Map.delete(input, required_field))

      assert [%{"message" => message}] = missing["errors"]

      field = Atom.to_string(required_field)
      assert message =~ "In field \"#{field}\""
      assert message =~ "Expected type"
    end)

    assert command_record_snapshot() == before_snapshot

    read_only =
      create_session_with_capabilities!(bootstrap, ["skeleton.read"], prefix: "graphql-read-only")

    Enum.each(seed.command_inputs, fn {name, input, _required_field} ->
      forbidden_input = Map.put(input, :idempotencyKey, unique_key("forbidden-#{name}"))

      response =
        conn
        |> Ash.PlugHelpers.set_actor(read_only)
        |> raw_command(name, forbidden_input)

      assert [%{"extensions" => %{"code" => "forbidden"}}] = response["errors"]
    end)

    assert command_record_snapshot() == before_snapshot
  end

  defp graphql(conn, query, variables) do
    response = raw_graphql(conn, query, variables)
    assert response["errors"] in [nil, []]
    response["data"] |> Map.values() |> hd()
  end

  defp raw_graphql(conn, query, variables) do
    conn
    |> post(~p"/graphql", %{query: query, variables: variables})
    |> json_response(200)
  end

  defp command(conn, name, input) do
    response = raw_command(conn, name, input)
    assert response["errors"] in [nil, []], inspect(response["errors"])
    response["data"] |> Map.values() |> hd()
  end

  defp raw_command(conn, name, input) do
    raw_graphql(conn, mutation(name), %{input: input})
  end

  defp mutation(:submit_manual_intake) do
    """
    mutation Command($input: SubmitManualIntakeInput!) {
      submitManualIntake(input: $input) {
        command operationId affectedIds { type id }
        normalizedEventId proposedChangeIds
      }
    }
    """
  end

  defp mutation(:apply_proposed_changes) do
    """
    mutation Command($input: ApplyProposedChangesInput!) {
      applyProposedChanges(input: $input) {
        command operationId affectedIds { type id }
        signal { id }
        task { id }
        reviewFinding { id }
        verificationCheck { id graphItemId }
      }
    }
    """
  end

  defp mutation(:create_work_packet) do
    """
    mutation Command($input: CreateWorkPacketInput!) {
      createWorkPacket(input: $input) {
        command operationId affectedIds { type id }
        packet { id currentVersionId }
        packetVersion { id versionNumber lifecycleState }
      }
    }
    """
  end

  defp mutation(:create_work_packet_version) do
    """
    mutation Command($input: CreateWorkPacketVersionInput!) {
      createWorkPacketVersion(input: $input) {
        command operationId affectedIds { type id }
        packet { id currentVersionId }
        packetVersion { id versionNumber lifecycleState }
      }
    }
    """
  end

  defp mutation(:start_work_run) do
    """
    mutation Command($input: StartWorkRunInput!) {
      startWorkRun(input: $input) {
        command operationId affectedIds { type id }
        run { id executionState verificationState }
        requiredChecks { id verificationCheckId state }
      }
    }
    """
  end

  defp mutation(:record_execution_observation) do
    """
    mutation Command($input: RecordExecutionObservationInput!) {
      recordExecutionObservation(input: $input) {
        command operationId affectedIds { type id }
        observation { id normalizedStatus }
        run { id executionState verificationState }
      }
    }
    """
  end

  defp mutation(:create_evidence_candidate) do
    """
    mutation Command($input: CreateEvidenceCandidateInput!) {
      createEvidenceCandidate(input: $input) {
        command operationId affectedIds { type id }
        evidenceCandidate { id candidateState }
      }
    }
    """
  end

  defp mutation(:accept_evidence) do
    """
    mutation Command($input: AcceptEvidenceInput!) {
      acceptEvidence(input: $input) {
        command operationId affectedIds { type id }
        evidenceCandidate { id candidateState }
        evidenceItem { id state }
        verificationResult { id result }
        run { id executionState verificationState }
      }
    }
    """
  end

  defp mutation(:waive_verification_check) do
    """
    mutation Command($input: WaiveVerificationCheckInput!) {
      waiveVerificationCheck(input: $input) {
        command operationId affectedIds { type id }
        verificationResult { id result }
        requiredCheck { id state }
        run { id executionState verificationState }
      }
    }
    """
  end

  defp assert_payload(payload, command, required_types) do
    assert payload["command"] == command
    assert is_binary(payload["operationId"])
    assert Enum.all?(payload["affectedIds"], &(is_binary(&1["id"]) and is_binary(&1["type"])))
    actual_types = MapSet.new(payload["affectedIds"], & &1["type"])
    assert MapSet.subset?(MapSet.new(required_types), actual_types)
  end

  defp stable_payload(payload) do
    %{
      "command" => payload["command"],
      "operationId" => payload["operationId"],
      "affectedIds" => payload["affectedIds"]
    }
  end

  defp packet_input(idempotency_key, source_ids, verification_check_ids) do
    %{
      idempotencyKey: idempotency_key,
      title: "GraphQL command packet",
      objective: "Exercise the complete operator command loop.",
      contextSummary: "The GraphQL transport advances one durable step at a time.",
      requirements: "Preserve authorization, replay, and transaction behavior.",
      successCriteria: "All required checks are accepted or waived.",
      autonomyPosture: "human_supervised",
      sourceGraphItemIds: source_ids,
      verificationCheckIds: verification_check_ids
    }
  end

  defp seed_command_targets(conn, check) do
    intake =
      command(conn, :submit_manual_intake, %{
        idempotencyKey: unique_key("guardrail-intake"),
        sourceIdentity: "manual:guardrail",
        replayIdentity: unique_key("guardrail-replay"),
        body: "Create guardrail command targets."
      })

    applied =
      command(conn, :apply_proposed_changes, %{
        idempotencyKey: unique_key("guardrail-apply"),
        normalizedEventId: intake["normalizedEventId"],
        proposedChangeIds: intake["proposedChangeIds"]
      })

    applied_check = applied["verificationCheck"]
    sources = [applied_check["graphItemId"], check.graph_item_id]
    checks = [applied_check["id"], check.id]
    packet_input = packet_input(unique_key("guardrail-packet"), sources, checks)
    packet = command(conn, :create_work_packet, packet_input)

    version_input =
      packet_input(unique_key("guardrail-version"), sources, checks)
      |> Map.merge(%{
        packetId: packet["packet"]["id"],
        expectedCurrentVersionId: packet["packetVersion"]["id"]
      })

    version = command(conn, :create_work_packet_version, version_input)

    run_input = %{
      idempotencyKey: unique_key("guardrail-run"),
      packetVersionId: version["packetVersion"]["id"],
      sourceSurface: "operator_commands_graphql_test",
      reason: "Create guardrail run targets.",
      authorityPosture: "human_supervised"
    }

    started = command(conn, :start_work_run, run_input)
    required_check = hd(started["requiredChecks"])

    observation_input = %{
      idempotencyKey: unique_key("guardrail-observation-operation"),
      runId: started["run"]["id"],
      verificationCheckId: applied_check["id"],
      sourceGraphItemId: applied_check["graphItemId"],
      observationSourceKind: "human",
      observationSourceIdentity: "manual:guardrail-observation",
      observationIdempotencyKey: unique_key("guardrail-observation-source"),
      observedStatus: "passed",
      normalizedStatus: "succeeded",
      freshnessState: "fresh",
      trustBasis: "owner_attested",
      observationRationale: "Guardrail observation."
    }

    observed = command(conn, :record_execution_observation, observation_input)

    candidate_input = %{
      idempotencyKey: unique_key("guardrail-candidate"),
      workRunId: started["run"]["id"],
      verificationCheckId: applied_check["id"],
      executionObservationId: observed["observation"]["id"],
      claim: "Guardrail candidate.",
      sourceKind: "human",
      sourceIdentity: "manual:guardrail-evidence",
      freshnessState: "fresh",
      trustBasis: "owner_attested",
      sensitivity: "internal"
    }

    candidate = command(conn, :create_evidence_candidate, candidate_input)

    accept_input = %{
      idempotencyKey: unique_key("guardrail-accept"),
      evidenceCandidateId: candidate["evidenceCandidate"]["id"],
      title: "Guardrail evidence",
      body: "Guardrail evidence body.",
      result: "passed",
      acceptancePolicyBasis: "owner_acceptance"
    }

    command_inputs = [
      {:submit_manual_intake,
       %{
         idempotencyKey: unique_key("missing-intake"),
         sourceIdentity: "manual:missing",
         replayIdentity: unique_key("missing-replay"),
         body: "Missing input test."
       }, :body},
      {:apply_proposed_changes,
       %{
         idempotencyKey: unique_key("missing-apply"),
         normalizedEventId: intake["normalizedEventId"],
         proposedChangeIds: intake["proposedChangeIds"]
       }, :proposedChangeIds},
      {:create_work_packet, Map.put(packet_input, :idempotencyKey, unique_key("missing-packet")),
       :title},
      {:create_work_packet_version,
       Map.put(version_input, :idempotencyKey, unique_key("missing-version")),
       :expectedCurrentVersionId},
      {:start_work_run, Map.put(run_input, :idempotencyKey, unique_key("missing-run")), :reason},
      {:record_execution_observation,
       Map.put(observation_input, :idempotencyKey, unique_key("missing-observation")),
       :normalizedStatus},
      {:create_evidence_candidate,
       Map.put(candidate_input, :idempotencyKey, unique_key("missing-candidate")), :claim},
      {:accept_evidence, accept_input, :body},
      {:waive_verification_check,
       %{
         idempotencyKey: unique_key("missing-waive"),
         runId: started["run"]["id"],
         runRequiredCheckId: required_check["id"],
         expectedExecutionState: started["run"]["executionState"],
         expectedVerificationState: started["run"]["verificationState"],
         reason: "Guardrail waiver.",
         policyBasis: "owner_exception"
       }, :reason}
    ]

    %{command_inputs: command_inputs}
  end

  # OperationCorrelation and AuthorizationDecision are deliberately excluded:
  # command start and authorization denial traces are expected to persist even
  # when the owning product command is rejected.
  defp command_record_snapshot do
    Map.new(@command_record_families, fn resource ->
      attribute_names =
        resource
        |> Ash.Resource.Info.attributes()
        |> Enum.map(& &1.name)

      rows =
        resource
        |> Ash.Query.select(attribute_names)
        |> Ash.read!(authorize?: false)
        |> Enum.map(&Map.take(&1, attribute_names))
        |> Enum.sort_by(&snapshot_row_sort_key/1)

      {resource, rows}
    end)
  end

  defp snapshot_row_sort_key(row), do: Map.get(row, :id) || inspect(row)

  defp create_required_verification_check(session, label) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "#{label} signal",
             body: "#{label} signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "#{label} task",
             body: "#{label} task body."
           }),
         {:ok, %{review_finding: finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "#{label} finding",
             body: "#{label} finding body."
           }),
         {:ok, %{verification_check: check}} <-
           WorkGraph.create_verification_check(session, operation, finding, %{
             title: "#{label} check",
             body: "#{label} check body."
           }) do
      {:ok, check}
    end
  end

  defp create_ready_packet(session, verification_checks) do
    OperatorCommandFixtures.create_ready_packet(session, verification_checks, %{
      title: "Least-capability command packet",
      objective: "Prove command target authorization.",
      context_summary: "The command target already exists in the operator workspace.",
      requirements: "Use only the command-specific capability.",
      success_criteria: "The command succeeds without skeleton.read.",
      autonomy_posture: "human_supervised"
    })
  end

  defp create_ready_run(session, verification_checks) do
    OperatorCommandFixtures.create_ready_run(
      session,
      verification_checks,
      %{
        title: "Least-capability command packet",
        objective: "Prove command target authorization.",
        context_summary: "The command target already exists in the operator workspace.",
        requirements: "Use only the command-specific capability.",
        success_criteria: "The command succeeds without skeleton.read.",
        autonomy_posture: "human_supervised"
      },
      %{
        source_surface: "operator_commands_graphql_test",
        reason: "Create a command target fixture.",
        authority_posture: "human_supervised"
      }
    )
  end

  defp record_observation(session, run, verification_check) do
    OperatorCommandFixtures.record_observation(
      session,
      run,
      verification_check,
      %{
        source_kind: "human",
        source_identity: "manual:accept-only-observation",
        idempotency_key: unique_key("accept-only-observation"),
        observed_status: "passed",
        normalized_status: "succeeded",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        rationale: "Create an acceptance target fixture."
      }
    )
  end

  defp create_candidate(session, run, verification_check, observation) do
    OperatorCommandFixtures.create_evidence_candidate(
      session,
      run,
      verification_check,
      observation,
      %{
        claim: "The command target fixture passed.",
        source_kind: "human",
        source_identity: "manual:accept-only-candidate",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        sensitivity: "internal"
      }
    )
  end

  defp unique_key(label), do: "#{label}:#{System.unique_integer([:positive, :monotonic])}"
end
