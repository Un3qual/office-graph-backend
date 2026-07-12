# Seeds for local development. Run with:
#
#     mix run priv/repo/seeds.exs

if Mix.env() in [:dev, :test] do
  defmodule OfficeGraph.RepoSeeds do
    @moduledoc false

    alias OfficeGraph.Foundation
    alias OfficeGraph.Integrations
    alias OfficeGraph.Integrations.NormalizedIntakeEvent
    alias OfficeGraph.Operations
    alias OfficeGraph.Projections
    alias OfficeGraph.ProposedChanges
    alias OfficeGraph.ProposedChanges.ProposedGraphChange
    alias OfficeGraph.Runs
    alias OfficeGraph.Verification
    alias OfficeGraph.WorkPackets

    require Ash.Query

    @seed_prefix "dev-seed"

    @seed_items [
      %{
        key: "pending-triage",
        state: :pending,
        body:
          "Customer onboarding is blocked on unclear ownership. Turn the support note into assigned work with an explicit verification check."
      },
      %{
        key: "ready-for-packet",
        state: :applied,
        body:
          "The finance approval checklist is stale. Prepare a governed work packet that verifies the current owner, required evidence, and completion criteria."
      },
      %{
        key: "verified-run",
        state: :verified,
        body:
          "The operator console needs a verified example run. Package the workflow, record fresh execution evidence, and mark the required check as satisfied.",
        packet_title: "Verify operator console demo run",
        objective: "Show a completed packet-backed run in the operator console.",
        context_summary:
          "A local development example that exercises intake, proposed changes, packet creation, run execution, and evidence acceptance.",
        requirements:
          "Create the packet from the applied intake, start a run, record a successful observation, and accept passing evidence.",
        success_criteria:
          "The run appears as verified and the run panel shows accepted evidence with no missing checks.",
        evidence_claim: "The local operator workflow demo completed successfully.",
        evidence_title: "Operator console demo evidence",
        evidence_body:
          "The development seed recorded a successful observation and accepted it as evidence for the required verification check."
      }
    ]

    def run do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      session = bootstrap.session

      seeded =
        Enum.map(@seed_items, fn item ->
          seed_item(session, item)
        end)

      IO.puts("Seeded Office Graph local owner and #{length(seeded)} operator workflow items.")
    end

    defp seed_item(session, %{state: :pending} = item) do
      {:ok, intake} = ensure_manual_intake(session, item)
      {:ok, %{key: item.key, event: intake.normalized_event, state: :pending}}
    end

    defp seed_item(session, %{state: :applied} = item) do
      {:ok, intake} = ensure_applied_intake(session, item)
      {:ok, %{key: item.key, event: intake.normalized_event, state: :applied}}
    end

    defp seed_item(session, %{state: :verified} = item) do
      {:ok, intake} = ensure_applied_intake(session, item)

      {:ok, workflow_item} =
        Projections.operator_workflow_item(session, intake.normalized_event.id)

      if workflow_item.status != "verified" do
        verification_link = verification_link!(workflow_item)
        {:ok, _accepted} = execute_verified_sequence(session, item, verification_link)
      end

      {:ok, %{key: item.key, event: intake.normalized_event, state: :verified}}
    end

    defp ensure_manual_intake(session, item) do
      case accepted_intake(session, item) do
        {:ok, nil} ->
          create_manual_intake(session, item)

        {:ok, event} ->
          {:ok,
           %{normalized_event: event, proposed_changes: proposed_changes_for(session, event)}}

        {:error, error} ->
          raise "failed to read seed intake #{item.key}: #{inspect(error)}"
      end
    end

    defp create_manual_intake(session, item) do
      {:ok, operation} =
        Operations.start_operation(session, :manual_intake_submit,
          idempotency_key: operation_key(item.key, "manual-intake")
        )

      Integrations.submit_manual_intake(session, operation, %{
        source_identity: source_identity(item),
        replay_identity: replay_identity(item),
        body: item.body
      })
    end

    defp ensure_applied_intake(session, item) do
      {:ok, intake} = ensure_manual_intake(session, item)

      case proposed_change_state(intake.proposed_changes) do
        :applied ->
          {:ok, intake}

        :pending ->
          {:ok, operation} =
            Operations.start_operation(session, :proposed_change_apply,
              idempotency_key: operation_key(item.key, "apply")
            )

          {:ok, applied} =
            ProposedChanges.apply_all(session, operation, intake.proposed_changes)

          {:ok, Map.put(intake, :applied, applied)}

        state ->
          raise "seed intake #{item.key} has unsupported proposed change state #{inspect(state)}"
      end
    end

    defp accepted_intake(session, item) do
      source_identity = source_identity(item)
      replay_identity = replay_identity(item)

      NormalizedIntakeEvent
      |> Ash.Query.filter(
        organization_id == ^session.organization_id and
          workspace_id == ^session.workspace_id and
          source_identity == ^source_identity and
          replay_identity == ^replay_identity and
          outcome == "accepted"
      )
      |> Ash.read_one(authorize?: false)
    end

    defp proposed_changes_for(session, event) do
      ProposedGraphChange
      |> Ash.Query.filter(
        organization_id == ^session.organization_id and
          workspace_id == ^session.workspace_id and
          normalized_event_id == ^event.id
      )
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.read!(authorize?: false)
    end

    defp proposed_change_state(proposed_changes) do
      statuses =
        proposed_changes
        |> Enum.map(& &1.status)
        |> Enum.uniq()

      case statuses do
        ["pending"] -> :pending
        ["applied"] -> :applied
        [] -> :empty
        other -> {:mixed, other}
      end
    end

    defp verification_link!(workflow_item) do
      Enum.find(workflow_item.graph_links, &(&1.type == "verification_check")) ||
        raise "seed item #{workflow_item.normalized_event_id} did not produce a verification check"
    end

    defp execute_verified_sequence(session, item, verification_link) do
      with {:ok, packet_result} <- create_seed_packet(session, item, verification_link),
           {:ok, run_result} <- start_seed_run(session, item, packet_result.version),
           {:ok, observation_result} <-
             record_seed_observation(session, item, verification_link, run_result.run),
           {:ok, candidate} <-
             create_seed_candidate(
               session,
               item,
               verification_link,
               run_result.run,
               observation_result.observation
             ),
           {:ok, accepted} <- accept_seed_evidence(session, item, candidate) do
        {:ok, accepted}
      end
    end

    defp create_seed_packet(session, item, verification_link) do
      attrs = packet_attrs(item, verification_link)

      with {:ok, operation} <-
             Operations.start_command(
               session,
               :work_packet_create,
               operation_key(item.key, "packet"),
               attrs
             ) do
        WorkPackets.create_packet(session, operation, attrs)
      end
    end

    defp start_seed_run(session, item, packet_version) do
      command_input = %{
        packet_version_id: packet_version.id,
        source_surface: "dev_seed",
        reason: "Seed local operator console data.",
        authority_posture: "human_supervised"
      }

      with {:ok, operation} <-
             Operations.start_command(
               session,
               :work_run_start,
               operation_key(item.key, "run"),
               command_input
             ) do
        {_packet_version_id, attrs} = Map.pop!(command_input, :packet_version_id)
        Runs.start_run(session, operation, packet_version, attrs)
      end
    end

    defp record_seed_observation(session, item, verification_link, run) do
      command_input = %{
        run_id: run.id,
        verification_check_id: verification_link.id,
        source_graph_item_id: verification_link.graph_item_id,
        observation_source_kind: "dev_seed",
        observation_source_identity: "#{@seed_prefix}:#{item.key}:observation",
        observation_idempotency_key: "#{@seed_prefix}:#{item.key}:observation",
        observed_status: "completed",
        normalized_status: "succeeded",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        observation_rationale: "Seeded local development success observation."
      }

      with {:ok, operation} <-
             Operations.start_command(
               session,
               :execution_observation_record,
               operation_key(item.key, "observation"),
               command_input
             ) do
        {_run_id, attrs} = Map.pop!(command_input, :run_id)

        attrs = %{
          source_kind: attrs.observation_source_kind,
          source_identity: attrs.observation_source_identity,
          idempotency_key: attrs.observation_idempotency_key,
          observed_status: attrs.observed_status,
          normalized_status: attrs.normalized_status,
          freshness_state: attrs.freshness_state,
          trust_basis: attrs.trust_basis,
          verification_check_id: attrs.verification_check_id,
          graph_item_id: attrs.source_graph_item_id,
          rationale: attrs.observation_rationale
        }

        Runs.record_observation(session, operation, run, attrs)
      end
    end

    defp create_seed_candidate(session, item, verification_link, run, observation) do
      attrs = %{
        work_run_id: run.id,
        verification_check_id: verification_link.id,
        execution_observation_id: observation.id,
        claim: item.evidence_claim,
        source_kind: "dev_seed",
        source_identity: "#{@seed_prefix}:#{item.key}:observation",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        sensitivity: "internal"
      }

      with {:ok, operation} <-
             Operations.start_command(
               session,
               :evidence_candidate_create,
               operation_key(item.key, "candidate"),
               attrs
             ) do
        Verification.create_evidence_candidate(session, operation, attrs)
      end
    end

    defp accept_seed_evidence(session, item, candidate) do
      command_input = %{
        evidence_candidate_id: candidate.id,
        title: item.evidence_title,
        body: item.evidence_body,
        result: "passed",
        acceptance_policy_basis: "local_development_seed"
      }

      with {:ok, operation} <-
             Operations.start_command(
               session,
               :evidence_accept,
               operation_key(item.key, "accept"),
               command_input
             ) do
        {_candidate_id, attrs} = Map.pop!(command_input, :evidence_candidate_id)
        Verification.accept_evidence_candidate(session, operation, candidate, attrs)
      end
    end

    defp packet_attrs(item, verification_link) do
      %{
        title: item.packet_title,
        objective: item.objective,
        context_summary: item.context_summary,
        requirements: item.requirements,
        success_criteria: item.success_criteria,
        autonomy_posture: "human_supervised",
        source_graph_item_ids: [verification_link.graph_item_id],
        verification_check_ids: [verification_link.id]
      }
    end

    defp source_identity(item), do: "#{@seed_prefix}:#{item.key}"
    defp replay_identity(item), do: "#{@seed_prefix}:#{item.key}:replay"
    defp operation_key(key, step), do: "#{@seed_prefix}:#{key}:#{step}"
  end

  OfficeGraph.RepoSeeds.run()
else
  IO.puts("Skipping Office Graph development seeds for #{Mix.env()}.")
end
