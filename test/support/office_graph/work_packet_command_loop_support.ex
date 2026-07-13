defmodule OfficeGraph.TestSupport.WorkPacketCommandLoopSupport do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use OfficeGraph.DataCase, async: false

      alias OfficeGraph.Foundation
      alias OfficeGraph.Operations
      alias OfficeGraph.QueryCounter
      alias OfficeGraph.Runs
      alias OfficeGraph.Authorization.AuthorizationDecision
      alias OfficeGraph.Runs.Changes.ValidateRunRequiredCheckContract
      alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
      alias OfficeGraph.Verification
      alias OfficeGraph.WorkGraph
      alias OfficeGraph.{Audit, Repo, Revisions}

      alias OfficeGraph.WorkGraph.{
        Artifact,
        EvidenceItem,
        EvidenceCandidate,
        GraphItem,
        GraphRelationship,
        ReviewFinding,
        Task,
        VerificationResult
      }

      alias OfficeGraph.WorkPackets

      alias OfficeGraph.WorkPackets.{
        WorkPacket,
        WorkPacketRequiredCheck,
        WorkPacketSourceReference,
        WorkPacketVersion
      }

      require Ash.Query

      defp create_packet_with_operation(session, idempotency_key, attrs) do
        {:ok, operation} =
          Operations.start_operation(session, :work_packet_create,
            idempotency_key: idempotency_key
          )

        WorkPackets.create_packet(session, operation, attrs)
      end

      defp start_waiver_command(session, key, run, required_check, attrs) do
        command_input =
          attrs
          |> Map.put(:run_id, run.id)
          |> Map.put(:run_required_check_id, required_check.id)

        Operations.start_command(session, :verification_waive, key, command_input)
      end

      defp create_ready_run(session, verification_check) when not is_list(verification_check) do
        create_ready_run(session, [verification_check])
      end

      defp create_ready_run(session, verification_checks) when is_list(verification_checks) do
        {:ok, packet_result} = create_ready_packet(session, verification_checks)
        {:ok, run_operation} = Operations.start_operation(session, :work_run_start)

        with {:ok, run_result} <-
               Runs.start_run(session, run_operation, packet_result.version, %{
                 source_surface: "test",
                 reason: "Execute ready packet.",
                 authority_posture: "human_supervised"
               }) do
          {:ok,
           run_result
           |> Map.put(:packet, packet_result.packet)
           |> Map.put(:packet_version, packet_result.version)}
        end
      end

      defp create_ready_packet(session, verification_checks) do
        {:ok, packet_operation} = Operations.start_operation(session, :work_packet_create)

        WorkPackets.create_packet(session, packet_operation, %{
          title: "Ready packet",
          objective: "Run selected work.",
          context_summary: "Ready context.",
          requirements: "Complete selected work.",
          success_criteria: "Required checks pass.",
          autonomy_posture: "human_supervised",
          source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
          verification_check_ids: Enum.map(verification_checks, & &1.id)
        })
      end

      defp direct_run_attrs(session, packet_result, operation) do
        %{
          id: Ecto.UUID.generate(),
          organization_id: session.organization_id,
          workspace_id: session.workspace_id,
          work_packet_id: packet_result.packet.id,
          work_packet_version_id: packet_result.version.id,
          operation_id: operation.id,
          initiator_principal_id: session.principal_id,
          objective: packet_result.version.objective,
          authority_posture: "human_supervised",
          source_surface: "test",
          reason: "Direct run create validates the packet contract."
        }
      end

      defp record_observation(session, run, verification_check, opts \\ []) do
        key = Keyword.get(opts, :key, Ecto.UUID.generate())
        normalized_status = Keyword.get(opts, :normalized_status, "succeeded")
        observed_status = Keyword.get(opts, :observed_status, "passed")
        freshness_state = Keyword.get(opts, :freshness_state, "fresh")
        trust_basis = Keyword.get(opts, :trust_basis, "owner_attested")

        {:ok, operation} =
          Operations.start_operation(session, :execution_observation_record,
            idempotency_key: "observation-operation:#{key}"
          )

        Runs.record_observation(session, operation, run, %{
          source_kind: "human",
          source_identity: "manual:#{key}",
          idempotency_key: "observation:#{key}",
          observed_status: observed_status,
          normalized_status: normalized_status,
          freshness_state: freshness_state,
          trust_basis: trust_basis,
          verification_check_id: verification_check.id,
          graph_item_id: verification_check.graph_item_id,
          rationale: "Human confirmed #{key}."
        })
      end

      defp create_evidence_candidate(session, run, verification_check, observation, opts) do
        key = Keyword.get(opts, :key, Ecto.UUID.generate())

        {:ok, operation} =
          Operations.start_operation(session, :evidence_candidate_create,
            idempotency_key: "candidate-operation:#{key}"
          )

        Verification.create_evidence_candidate(session, operation, %{
          work_run_id: run.id,
          verification_check_id: verification_check.id,
          execution_observation_id: observation.id,
          artifact_id: Keyword.get(opts, :artifact_id),
          claim: "Evidence candidate #{key}.",
          source_kind: "human",
          source_identity: "manual:#{key}",
          freshness_state: Keyword.get(opts, :freshness_state, "fresh"),
          trust_basis: Keyword.get(opts, :trust_basis, "owner_attested"),
          sensitivity: "internal"
        })
      end

      defp accept_candidate(session, candidate, opts) do
        key = Keyword.get(opts, :key, Ecto.UUID.generate())

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

      defp create_required_verification_check(session) do
        with {:ok, graph} <- create_required_verification_graph(session) do
          {:ok, graph.verification_check}
        end
      end

      defp create_required_verification_graph(session) do
        {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

        with {:ok, %{signal: signal}} <-
               WorkGraph.create_signal(session, operation, %{
                 title: "Launch signal",
                 body: "Launch signal body."
               }),
             {:ok, %{task: task}} <-
               WorkGraph.create_task(session, operation, signal, %{
                 title: "Launch task",
                 body: "Launch task body."
               }),
             {:ok, %{review_finding: review_finding}} <-
               WorkGraph.create_review_finding(session, operation, task, %{
                 title: "Launch finding",
                 body: "Launch finding body."
               }),
             {:ok, %{verification_check: verification_check}} <-
               WorkGraph.create_verification_check(session, operation, review_finding, %{
                 title: "Launch check",
                 body: "Launch check body."
               }) do
          {:ok,
           %{
             signal: signal,
             task: task,
             review_finding: review_finding,
             verification_check: verification_check
           }}
        end
      end

      defp fetch_resource!(resource, id) do
        resource_id = id

        resource
        |> Ash.Query.filter(id: resource_id)
        |> Ash.read_one!(authorize?: false)
      end

      defp relationship_exists?(source_item_id, target_item_id, relationship_type) do
        expected_source_id = source_item_id
        expected_target_id = target_item_id
        expected_type = relationship_type

        GraphRelationship
        |> Ash.Query.filter(
          source_item_id: expected_source_id,
          target_item_id: expected_target_id,
          relationship_type: expected_type
        )
        |> Ash.exists?(authorize?: false)
      end

      defp accepted_evidence_for_candidate?(candidate_id) do
        expected_candidate_id = candidate_id

        EvidenceItem
        |> Ash.Query.filter(candidate_id: expected_candidate_id)
        |> Ash.exists?(authorize?: false)
      end

      defp run_for_operation?(operation_id) do
        expected_operation_id = operation_id

        Run
        |> Ash.Query.filter(operation_id: expected_operation_id)
        |> Ash.exists?(authorize?: false)
      end

      defp verification_result_for_candidate_target?(candidate) do
        expected_check_id = candidate.verification_check_id
        expected_run_id = candidate.work_run_id

        VerificationResult
        |> Ash.Query.filter(
          verification_check_id: expected_check_id,
          work_run_id: expected_run_id
        )
        |> Ash.exists?(authorize?: false)
      end

      defp insert_artifact!(bootstrap, title) do
        artifact_id = Ecto.UUID.generate()

        {:ok, graph_item} =
          Ash.create(
            GraphItem,
            %{
              id: Ecto.UUID.generate(),
              organization_id: bootstrap.organization.id,
              workspace_id: bootstrap.workspace.id,
              resource_type: "artifact",
              resource_id: artifact_id,
              title: "#{title} graph item"
            },
            action: :create,
            authorize?: false
          )

        Ash.create!(
          Artifact,
          %{
            id: artifact_id,
            organization_id: bootstrap.organization.id,
            workspace_id: bootstrap.workspace.id,
            graph_item_id: graph_item.id,
            title: title,
            uri: "https://example.test/#{artifact_id}"
          },
          action: :create,
          authorize?: false
        )
      end

      defp insert_malformed_execution_observation!(session, operation, run, verification_check) do
        id = Ecto.UUID.generate()
        now = DateTime.utc_now()

        Repo.query!(
          """
          INSERT INTO execution_observations (
            id,
            organization_id,
            workspace_id,
            work_run_id,
            operation_id,
            verification_check_id,
            graph_item_id,
            source_kind,
            source_identity,
            idempotency_key,
            observed_status,
            normalized_status,
            ingested_at,
            freshness_state,
            trust_basis,
            rationale,
            metadata,
            inserted_at,
            updated_at
          )
          VALUES (
            $1::uuid,
            $2::uuid,
            $3::uuid,
            $4::uuid,
            $5::uuid,
            $6::uuid,
            $7::uuid,
            'human',
            'manual:malformed-summary-observation',
            'malformed-summary-observation',
            'passed',
            'succeeded',
            $8,
            'fresh',
            'owner_attested',
            'Malformed legacy row.',
            '{}'::jsonb,
            $8,
            $8
          )
          """,
          [
            db_uuid(id),
            db_uuid(session.organization_id),
            db_uuid(session.workspace_id),
            db_uuid(run.id),
            db_uuid(operation.id),
            db_uuid(verification_check.id),
            db_uuid(verification_check.graph_item_id),
            now
          ]
        )

        id
      end

      defp delete_run_required_check!(run_id, verification_check_id) do
        Repo.query!(
          """
          DELETE FROM run_required_checks
          WHERE run_id = $1::uuid AND verification_check_id = $2::uuid
          """,
          [db_uuid(run_id), db_uuid(verification_check_id)]
        )
      end

      defp insert_non_packet_run!(session, work_packet_id) do
        run_id = Ecto.UUID.generate()

        Repo.query!(
          """
          INSERT INTO runs (
            id,
            organization_id,
            workspace_id,
            work_packet_id,
            work_packet_version_id,
            state,
            inserted_at,
            updated_at
          )
          VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, NULL, 'running', NOW(), NOW())
          """,
          [
            db_uuid(run_id),
            db_uuid(session.organization_id),
            db_uuid(session.workspace_id),
            db_uuid(work_packet_id)
          ]
        )

        run_id
      end

      defp bootstrap_local_owner_for(suffix) do
        Foundation.bootstrap_local_owner(
          organization_name: "Organization #{suffix}",
          organization_slug: suffix,
          workspace_name: "Workspace #{suffix}",
          workspace_slug: "workspace-#{suffix}",
          initiative_name: "Initiative #{suffix}",
          initiative_slug: "initiative-#{suffix}",
          owner_email: "owner-#{suffix}@office-graph.local",
          owner_name: "Owner #{suffix}"
        )
      end

      defp forge_packet_current_version!(packet_id, version_id) do
        Repo.query!(
          """
          UPDATE work_packets
          SET current_version_id = $1::uuid
          WHERE id = $2::uuid
          """,
          [db_uuid(version_id), db_uuid(packet_id)]
        )
      end

      defp blank_packet_execution_context!(version_id) do
        Repo.query!(
          """
          UPDATE work_packet_versions
          SET context_summary = '', requirements = ''
          WHERE id = $1::uuid
          """,
          [db_uuid(version_id)]
        )
      end

      defp run_exists_for_operation?(operation_id) do
        expected_operation_id = operation_id

        Run
        |> Ash.Query.filter(operation_id: expected_operation_id)
        |> Ash.exists?(authorize?: false)
      end

      defp db_uuid(value), do: Ecto.UUID.dump!(value)
    end
  end
end
