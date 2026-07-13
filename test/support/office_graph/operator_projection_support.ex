# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
defmodule OfficeGraph.TestSupport.OperatorProjectionSupport do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
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

        assert row =
                 Enum.find(inbox.rows, &(&1.normalized_event_id == intake.normalized_event.id))

        assert row.status == expected_status
        assert row.allowed_next_actions == []
      end

      defp complete_linked_run(session, run, verification_check, key, "verified") do
        {:ok, observation_result} = record_observation(session, run, verification_check, key: key)

        {:ok, candidate} =
          create_evidence_candidate(
            session,
            run,
            verification_check,
            observation_result.observation,
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
          create_evidence_candidate(
            session,
            run,
            verification_check,
            observation_result.observation,
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
  end
end
