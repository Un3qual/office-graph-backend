defmodule OfficeGraph.Projections.RunState do
  @moduledoc false

  alias OfficeGraph.Projections.CommandAffordance
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph.EvidenceCandidate
  alias OfficeGraph.WorkGraph.VerificationCheck

  require Ash.Query

  @child_summary_limit 20

  def operator_run_state(session_context, run_id) do
    with {:ok, summary} <- Runs.get_summary(session_context, run_id),
         {:ok, evidence_candidates} <- read_evidence_candidates(session_context, summary.run.id),
         {:ok, verification_checks} <- read_verification_checks(session_context, summary) do
      {:ok, build_run_state(session_context, summary, evidence_candidates, verification_checks)}
    end
  end

  def verification_outcome(session_context, run_id) do
    with {:ok, run_state} <- operator_run_state(session_context, run_id) do
      {:ok,
       %{
         type: "verification_outcome",
         status: run_state.status,
         run: run_state.run,
         verification_results: run_state.verification_results,
         missing_evidence: run_state.missing_evidence,
         source_watermark: run_state.source_watermark
       }}
    end
  end

  defp read_evidence_candidates(session_context, run_id) do
    EvidenceCandidate
    |> Ash.Query.filter(
      work_run_id == ^run_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_verification_checks(session_context, summary) do
    check_ids = Enum.map(summary.required_checks, & &1.verification_check_id)

    VerificationCheck
    |> Ash.Query.filter(
      id in ^check_ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read(actor: session_context)
  end

  defp build_run_state(session_context, summary, evidence_candidates, verification_checks) do
    status = run_status(summary, evidence_candidates)
    verification_checks_by_id = Map.new(verification_checks, &{&1.id, &1})

    command_affordances =
      run_command_affordances(session_context, status, summary, evidence_candidates)

    %{
      type: "operator_run_state",
      status: status,
      allowed_next_actions: CommandAffordance.enabled_identities(command_affordances),
      command_affordances: command_affordances,
      command_options: command_options(summary, evidence_candidates, verification_checks_by_id),
      activity: run_activity(summary, evidence_candidates, verification_checks_by_id),
      child_summary: child_summary(summary, evidence_candidates),
      source_watermark: source_watermark(summary, evidence_candidates, status),
      packet: %{
        id: summary.packet.id,
        title: summary.packet.title,
        state: summary.packet.state
      },
      packet_version: %{
        id: summary.packet_version.id,
        version_number: summary.packet_version.version_number,
        lifecycle_state: summary.packet_version.lifecycle_state,
        objective: summary.packet_version.objective
      },
      run: %{
        id: summary.run.id,
        aggregate_state: summary.run.aggregate_state,
        execution_state: summary.run.execution_state,
        verification_state: summary.run.verification_state
      },
      required_checks:
        summary.required_checks
        |> Enum.take(@child_summary_limit)
        |> Enum.map(fn required_check ->
          %{
            id: required_check.id,
            verification_check_id: required_check.verification_check_id,
            graph_item_id:
              get_in(verification_checks_by_id, [
                required_check.verification_check_id,
                Access.key(:graph_item_id)
              ]),
            state: required_check.state
          }
        end),
      observations:
        summary.observations
        |> Enum.take(@child_summary_limit)
        |> Enum.map(fn observation ->
          %{
            id: observation.id,
            verification_check_id: observation.verification_check_id,
            graph_item_id: observation.graph_item_id,
            normalized_status: observation.normalized_status,
            freshness_state: observation.freshness_state,
            trust_basis: observation.trust_basis,
            source_kind: observation.source_kind,
            source_identity: observation.source_identity
          }
        end),
      evidence_candidates:
        evidence_candidates
        |> Enum.take(@child_summary_limit)
        |> Enum.map(&evidence_candidate_projection/1),
      evidence_items:
        summary.evidence_items
        |> Enum.take(@child_summary_limit)
        |> Enum.map(fn evidence_item ->
          %{
            id: evidence_item.id,
            state: evidence_item.state,
            candidate_id: evidence_item.candidate_id,
            work_run_id: evidence_item.work_run_id
          }
        end),
      verification_results:
        summary.verification_results
        |> Enum.take(@child_summary_limit)
        |> Enum.map(fn result ->
          %{
            id: result.id,
            result: result.result,
            verification_check_id: result.verification_check_id,
            evidence_item_id: result.evidence_item_id,
            operation_id: result.operation_id,
            actor_principal_id: result.actor_principal_id,
            policy_basis: result.policy_basis,
            target_graph_item_id: result.target_graph_item_id,
            work_run_id: result.work_run_id,
            work_packet_version_id: result.work_packet_version_id
          }
        end),
      missing_evidence:
        summary.missing_evidence
        |> Enum.take(@child_summary_limit)
        |> Enum.map(&missing_evidence_projection/1)
    }
  end

  defp child_summary(summary, evidence_candidates) do
    counts = %{
      required_checks: length(summary.required_checks),
      observations: length(summary.observations),
      evidence_candidates: length(evidence_candidates),
      evidence_items: length(summary.evidence_items),
      verification_results: length(summary.verification_results),
      missing_evidence: length(summary.missing_evidence)
    }

    Map.put(
      counts,
      :has_more?,
      Enum.any?(counts, fn {_kind, count} -> count > @child_summary_limit end)
    )
  end

  defp run_activity(summary, evidence_candidates, verification_checks_by_id) do
    required =
      Enum.map(summary.required_checks, fn check ->
        verification_check = Map.get(verification_checks_by_id, check.verification_check_id)

        activity_item(
          "required_check",
          check.id,
          verification_check && verification_check.title,
          check.state
        )
      end)

    observations =
      Enum.map(summary.observations, fn observation ->
        activity_item(
          "observation",
          observation.id,
          observation.source_identity,
          observation.normalized_status
        )
      end)

    candidates =
      Enum.map(evidence_candidates, fn candidate ->
        activity_item(
          "evidence_candidate",
          candidate.id,
          candidate.claim,
          candidate.candidate_state
        )
      end)

    evidence_items =
      Enum.map(summary.evidence_items, fn item ->
        activity_item("evidence_item", item.id, "Accepted evidence", item.state)
      end)

    results =
      Enum.map(summary.verification_results, fn result ->
        activity_item("verification_result", result.id, result.policy_basis, result.result)
      end)

    missing =
      Enum.map(summary.missing_evidence, fn item ->
        verification_check = Map.get(verification_checks_by_id, item.verification_check_id)

        activity_item(
          "missing_evidence",
          item.verification_check_id,
          verification_check && verification_check.title,
          item.reason
        )
      end)

    required ++ observations ++ candidates ++ evidence_items ++ results ++ missing
  end

  defp activity_item(kind, id, title, status) do
    %{kind: kind, stable_id: id, title: title || kind, status: status}
  end

  defp command_options(summary, evidence_candidates, verification_checks_by_id) do
    %{
      observation: observation_options(summary, verification_checks_by_id),
      evidence_candidate: evidence_candidate_options(summary, verification_checks_by_id),
      evidence_acceptance:
        evidence_acceptance_options(summary, evidence_candidates, verification_checks_by_id),
      waiver: waiver_options(summary, verification_checks_by_id)
    }
  end

  defp observation_options(summary, verification_checks_by_id) do
    check_ids = MapSet.new(checks_needing_observations(summary))

    summary.required_checks
    |> Enum.filter(&MapSet.member?(check_ids, &1.verification_check_id))
    |> Enum.flat_map(fn required_check ->
      case Map.get(verification_checks_by_id, required_check.verification_check_id) do
        %{id: check_id, graph_item_id: graph_item_id, title: title}
        when is_binary(graph_item_id) and is_binary(title) ->
          [
            %{
              key: required_check.id,
              label: title,
              run_id: summary.run.id,
              verification_check_id: check_id,
              source_graph_item_id: graph_item_id,
              observation_source_kind: "human",
              observation_source_identity: "operator-console",
              freshness_state: "fresh",
              trust_basis: "owner_attested"
            }
          ]

        _missing_or_redacted ->
          []
      end
    end)
  end

  defp evidence_candidate_options(summary, verification_checks_by_id) do
    summary
    |> candidate_eligible_observations()
    |> Enum.flat_map(fn observation ->
      case Map.get(verification_checks_by_id, observation.verification_check_id) do
        %{id: check_id, title: title} when is_binary(title) ->
          [
            %{
              key: observation.id,
              label: title,
              work_run_id: summary.run.id,
              verification_check_id: check_id,
              execution_observation_id: observation.id,
              source_kind: observation.source_kind,
              source_identity: observation.source_identity,
              freshness_state: observation.freshness_state,
              trust_basis: observation.trust_basis,
              sensitivity: "internal"
            }
          ]

        _missing_or_redacted ->
          []
      end
    end)
    |> Enum.filter(&complete_string_option?/1)
  end

  defp evidence_acceptance_options(summary, evidence_candidates, verification_checks_by_id) do
    missing_check_ids = MapSet.new(summary.missing_evidence, & &1.verification_check_id)

    evidence_candidates
    |> Enum.filter(&acceptable_pending_candidate?(&1, missing_check_ids))
    |> Enum.flat_map(fn candidate ->
      case Map.get(verification_checks_by_id, candidate.verification_check_id) do
        %{title: title} when is_binary(title) ->
          [
            %{
              key: candidate.id,
              label: title,
              evidence_candidate_id: candidate.id,
              result: "passed",
              acceptance_policy_basis: "owner_acceptance"
            }
          ]

        _missing_or_redacted ->
          []
      end
    end)
    |> Enum.filter(&complete_string_option?/1)
  end

  defp waiver_options(summary, verification_checks_by_id) do
    summary
    |> pending_required_checks()
    |> Enum.flat_map(fn required_check ->
      case Map.get(verification_checks_by_id, required_check.verification_check_id) do
        %{title: title} when is_binary(title) ->
          [
            %{
              key: required_check.id,
              label: title,
              run_id: summary.run.id,
              run_required_check_id: required_check.id,
              expected_execution_state: summary.run.execution_state,
              expected_verification_state: summary.run.verification_state,
              policy_basis: "owner_exception"
            }
          ]

        _missing_or_redacted ->
          []
      end
    end)
    |> Enum.filter(&complete_string_option?/1)
  end

  defp complete_string_option?(option) do
    Enum.all?(option, fn {_key, value} -> is_binary(value) and String.trim(value) != "" end)
  end

  defp run_status(summary, _evidence_candidates)
       when summary.run.verification_state == "verified" or
              summary.run.aggregate_state == "verified" do
    "verified"
  end

  defp run_status(summary, _evidence_candidates)
       when summary.run.aggregate_state == "failed" or summary.run.verification_state == "failed" do
    "failed"
  end

  defp run_status(summary, evidence_candidates) do
    cond do
      pending_candidate_for_missing_check?(summary, evidence_candidates) ->
        "awaiting_evidence_acceptance"

      summary.observations != [] and summary.missing_evidence != [] ->
        "awaiting_evidence"

      summary.observations == [] ->
        "awaiting_execution"

      true ->
        "awaiting_evidence"
    end
  end

  defp run_command_affordances(
         session_context,
         "awaiting_execution",
         summary,
         _evidence_candidates
       ) do
    record_observation_affordance(session_context, summary)
    |> Kernel.++(waive_verification_check_affordance(session_context, summary))
  end

  defp run_command_affordances(
         session_context,
         "awaiting_evidence",
         summary,
         _evidence_candidates
       ) do
    record_observation_affordance(session_context, summary)
    |> Kernel.++(create_evidence_candidate_affordance(session_context, summary))
    |> Kernel.++(waive_verification_check_affordance(session_context, summary))
  end

  defp run_command_affordances(
         session_context,
         "awaiting_evidence_acceptance",
         summary,
         evidence_candidates
       ) do
    record_observation_affordance(session_context, summary)
    |> Kernel.++(accept_evidence_affordance(session_context, summary, evidence_candidates))
    |> Kernel.++(waive_verification_check_affordance(session_context, summary))
  end

  defp run_command_affordances(_session_context, _status, _summary, _evidence_candidates), do: []

  defp record_observation_affordance(session_context, summary) do
    case checks_needing_observations(summary) do
      [] ->
        []

      check_ids ->
        if CommandAffordance.authorized?(session_context, :execution_observation_record) do
          [
            CommandAffordance.enabled(
              "record_execution_observation",
              "Record execution observations for this run.",
              required_fields: CommandAffordance.observation_required_fields(),
              input_defaults: [CommandAffordance.input_default("run_id", summary.run.id)],
              target_ids:
                [CommandAffordance.target_id("work_run", summary.run.id)] ++
                  Enum.map(
                    check_ids,
                    &CommandAffordance.target_id("verification_check", &1)
                  )
            )
          ]
        else
          [CommandAffordance.policy_restricted("record_execution_observation")]
        end
    end
  end

  defp create_evidence_candidate_affordance(session_context, summary) do
    if candidate_eligible_observations(summary) == [] do
      []
    else
      if CommandAffordance.authorized?(session_context, :evidence_candidate_create) do
        [
          CommandAffordance.enabled(
            "create_evidence_candidate",
            "Create an evidence candidate for missing verification evidence.",
            required_fields: [
              "work_run_id",
              "verification_check_id",
              "execution_observation_id",
              "claim",
              "source_kind",
              "source_identity",
              "freshness_state",
              "trust_basis",
              "sensitivity"
            ],
            input_defaults: candidate_input_defaults(summary),
            target_ids: run_target_ids(summary) ++ observation_target_ids(summary)
          )
        ]
      else
        [CommandAffordance.policy_restricted("create_evidence_candidate")]
      end
    end
  end

  defp accept_evidence_affordance(session_context, summary, evidence_candidates) do
    if CommandAffordance.authorized?(session_context, :evidence_accept) do
      [
        CommandAffordance.enabled(
          "accept_evidence",
          "Accept a candidate as evidence for a missing check.",
          required_fields: [
            "evidence_candidate_id",
            "title",
            "body",
            "result",
            "acceptance_policy_basis"
          ],
          target_ids:
            run_target_ids(summary) ++
              acceptable_candidate_target_ids(summary, evidence_candidates)
        )
      ]
    else
      [CommandAffordance.policy_restricted("accept_evidence")]
    end
  end

  defp candidate_input_defaults(summary) do
    eligible_observations = candidate_eligible_observations(summary)

    eligible_check_ids =
      eligible_observations
      |> Enum.map(& &1.verification_check_id)
      |> MapSet.new()

    [
      CommandAffordance.input_default("work_run_id", summary.run.id),
      CommandAffordance.input_default(
        "verification_check_id",
        summary.missing_evidence
        |> Enum.map(& &1.verification_check_id)
        |> Enum.filter(&MapSet.member?(eligible_check_ids, &1))
      ),
      CommandAffordance.input_default(
        "execution_observation_id",
        Enum.map(eligible_observations, & &1.id)
      ),
      CommandAffordance.input_default("sensitivity", "internal")
    ]
  end

  defp candidate_eligible_observations(summary) do
    missing_check_ids = MapSet.new(summary.missing_evidence, & &1.verification_check_id)

    Enum.filter(summary.observations, fn observation ->
      MapSet.member?(missing_check_ids, observation.verification_check_id) and
        observation.normalized_status == "succeeded" and
        Verification.acceptable_evidence_source?(observation)
    end)
  end

  defp checks_needing_observations(summary) do
    observed_check_ids =
      summary
      |> candidate_eligible_observations()
      |> MapSet.new(& &1.verification_check_id)

    summary.missing_evidence
    |> Enum.map(& &1.verification_check_id)
    |> Enum.reject(&MapSet.member?(observed_check_ids, &1))
  end

  defp waive_verification_check_affordance(session_context, summary) do
    if CommandAffordance.authorized?(session_context, :verification_waive) do
      [
        CommandAffordance.enabled(
          "waive_verification_check",
          "Waive a pending required check under an approved exception.",
          required_fields: [
            "run_id",
            "run_required_check_id",
            "expected_execution_state",
            "expected_verification_state",
            "reason",
            "policy_basis"
          ],
          input_defaults: waiver_input_defaults(summary),
          target_ids: waiver_target_ids(summary)
        )
      ]
    else
      []
    end
  end

  defp waiver_input_defaults(summary) do
    [
      CommandAffordance.input_default("run_id", summary.run.id),
      CommandAffordance.input_default(
        "run_required_check_id",
        Enum.map(pending_required_checks(summary), & &1.id)
      ),
      CommandAffordance.input_default(
        "expected_execution_state",
        summary.run.execution_state
      ),
      CommandAffordance.input_default(
        "expected_verification_state",
        summary.run.verification_state
      )
    ]
  end

  defp waiver_target_ids(summary) do
    [CommandAffordance.target_id("work_run", summary.run.id)] ++
      Enum.map(
        pending_required_checks(summary),
        &CommandAffordance.target_id("run_required_check", &1.id)
      )
  end

  defp pending_required_checks(summary) do
    Enum.filter(summary.required_checks, &(&1.state == "pending"))
  end

  defp pending_candidate_for_missing_check?(summary, evidence_candidates) do
    missing_check_ids = MapSet.new(summary.missing_evidence, & &1.verification_check_id)

    Enum.any?(evidence_candidates, &acceptable_pending_candidate?(&1, missing_check_ids))
  end

  defp run_target_ids(summary) do
    check_targets =
      Enum.map(summary.missing_evidence, fn missing ->
        CommandAffordance.target_id("verification_check", missing.verification_check_id)
      end)

    [CommandAffordance.target_id("work_run", summary.run.id) | check_targets]
    |> CommandAffordance.compact_target_ids()
  end

  defp observation_target_ids(summary) do
    summary.observations
    |> Enum.map(&CommandAffordance.target_id("execution_observation", &1.id))
    |> CommandAffordance.compact_target_ids()
  end

  defp acceptable_candidate_target_ids(summary, evidence_candidates) do
    missing_check_ids = MapSet.new(summary.missing_evidence, & &1.verification_check_id)

    evidence_candidates
    |> Enum.filter(&acceptable_pending_candidate?(&1, missing_check_ids))
    |> Enum.map(&CommandAffordance.target_id("evidence_candidate", &1.id))
    |> CommandAffordance.compact_target_ids()
  end

  defp acceptable_pending_candidate?(candidate, missing_check_ids) do
    candidate.candidate_state == "candidate" and
      MapSet.member?(missing_check_ids, candidate.verification_check_id) and
      Verification.acceptable_evidence_source?(candidate)
  end

  defp evidence_candidate_projection(candidate) do
    %{
      id: candidate.id,
      verification_check_id: candidate.verification_check_id,
      execution_observation_id: candidate.execution_observation_id,
      claim: candidate.claim,
      state: candidate.candidate_state,
      freshness_state: candidate.freshness_state,
      trust_basis: candidate.trust_basis,
      source_kind: candidate.source_kind,
      source_identity: candidate.source_identity
    }
  end

  defp missing_evidence_projection(%{
         verification_check_id: verification_check_id,
         reason: reason
       }) do
    %{verification_check_id: verification_check_id, reason: reason}
  end

  defp source_watermark(summary, evidence_candidates, status) do
    %{
      status: status,
      packet: %{
        id: summary.packet.id,
        title: summary.packet.title,
        state: summary.packet.state
      },
      packet_version: %{
        id: summary.packet_version.id,
        version_number: summary.packet_version.version_number,
        lifecycle_state: summary.packet_version.lifecycle_state,
        objective: summary.packet_version.objective
      },
      run: %{
        id: summary.run.id,
        aggregate_state: summary.run.aggregate_state,
        execution_state: summary.run.execution_state,
        verification_state: summary.run.verification_state
      },
      required_checks:
        Enum.map(summary.required_checks, fn required_check ->
          %{
            id: required_check.id,
            verification_check_id: required_check.verification_check_id,
            state: required_check.state
          }
        end),
      observations:
        Enum.map(summary.observations, fn observation ->
          %{
            id: observation.id,
            verification_check_id: observation.verification_check_id,
            graph_item_id: observation.graph_item_id,
            normalized_status: observation.normalized_status,
            freshness_state: observation.freshness_state,
            trust_basis: observation.trust_basis,
            source_kind: observation.source_kind,
            source_identity: observation.source_identity
          }
        end),
      evidence_candidates: Enum.map(evidence_candidates, &evidence_candidate_projection/1),
      evidence_items:
        Enum.map(summary.evidence_items, fn evidence_item ->
          %{
            id: evidence_item.id,
            state: evidence_item.state,
            candidate_id: evidence_item.candidate_id,
            work_run_id: evidence_item.work_run_id
          }
        end),
      verification_results:
        Enum.map(summary.verification_results, fn result ->
          %{
            id: result.id,
            result: result.result,
            verification_check_id: result.verification_check_id,
            evidence_item_id: result.evidence_item_id,
            operation_id: result.operation_id,
            actor_principal_id: result.actor_principal_id,
            policy_basis: result.policy_basis,
            target_graph_item_id: result.target_graph_item_id,
            work_run_id: result.work_run_id,
            work_packet_version_id: result.work_packet_version_id
          }
        end),
      missing_evidence: Enum.map(summary.missing_evidence, &missing_evidence_projection/1)
    }
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
