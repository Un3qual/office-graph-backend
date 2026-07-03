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
    alias OfficeGraph.PacketRunVerification
    alias OfficeGraph.Projections
    alias OfficeGraph.ProposedChanges
    alias OfficeGraph.ProposedChanges.ProposedGraphChange

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

      verification_link = verification_link!(workflow_item)

      {:ok, _summary} =
        PacketRunVerification.execute(
          session,
          packet_run_input(item, verification_link)
        )

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

    defp packet_run_input(item, verification_link) do
      %{
        flow_identity: "#{@seed_prefix}:#{item.key}:packet-run",
        verification_check_id: verification_link.id,
        source_graph_item_id: verification_link.graph_item_id,
        packet_title: item.packet_title,
        objective: item.objective,
        context_summary: item.context_summary,
        requirements: item.requirements,
        success_criteria: item.success_criteria,
        autonomy_posture: "human_supervised",
        source_surface: "dev_seed",
        reason: "Seed local operator console data.",
        authority_posture: "human_supervised",
        observation_source_kind: "dev_seed",
        observation_source_identity: "#{@seed_prefix}:#{item.key}:observation",
        observation_idempotency_key: "#{@seed_prefix}:#{item.key}:observation",
        observed_status: "completed",
        normalized_status: "succeeded",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        observation_rationale: "Seeded local development success observation.",
        evidence_claim: item.evidence_claim,
        evidence_title: item.evidence_title,
        evidence_body: item.evidence_body,
        evidence_result: "passed",
        acceptance_policy_basis: "local_development_seed"
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
