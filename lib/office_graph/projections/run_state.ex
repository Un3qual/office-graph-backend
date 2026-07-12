defmodule OfficeGraph.Projections.RunState do
  @moduledoc false

  alias OfficeGraph.Projections.CommandAffordance
  alias OfficeGraph.Projections.KeysetCursor
  alias OfficeGraph.{Authorization, Repo}
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph.EvidenceCandidate
  alias OfficeGraph.WorkGraph.VerificationCheck

  require Ash.Query

  @child_summary_limit 20

  def operator_run_state(session_context, run_id) do
    with {:ok, summary} <-
           Runs.get_projection_summary(session_context, run_id, @child_summary_limit),
         {:ok, evidence_candidates} <-
           read_evidence_candidates(session_context, summary.run.id, @child_summary_limit),
         {:ok, verification_checks} <- read_verification_checks(session_context, summary),
         {:ok, command_option_summary} <-
           read_command_option_summary(session_context, summary.run.id) do
      {:ok,
       build_run_state(
         session_context,
         summary,
         evidence_candidates,
         verification_checks,
         command_option_summary
       )}
    end
  end

  def activity_page(session_context, run_id, opts) do
    limit = Keyword.fetch!(opts, :limit)
    after_cursor = Keyword.get(opts, :after_cursor)

    with :ok <-
           Authorization.authorize_projection(session_context, :skeleton_read,
             organization_id: session_context.organization_id
           ),
         {:ok, after_key} <- decode_activity_cursor(after_cursor),
         {:ok, %{rows: rows}} <-
           Repo.query(
             activity_sql(),
             activity_params(session_context, run_id, after_key, limit + 1)
           ) do
      page_rows = Enum.take(rows, limit)

      {:ok,
       %{
         edges: Enum.map(page_rows, &activity_edge/1),
         has_next_page?: length(rows) > limit,
         has_previous_page?: not is_nil(after_cursor)
       }}
    end
  end

  def command_option_page(session_context, run_id, kind, opts) do
    limit = Keyword.fetch!(opts, :limit)
    after_cursor = Keyword.get(opts, :after_cursor)

    with true <- kind in ["observation", "evidence_candidate", "evidence_acceptance", "waiver"],
         {:ok, run_id} <- normalize_run_id(run_id),
         :ok <-
           Authorization.authorize_projection(session_context, :skeleton_read,
             organization_id: session_context.organization_id
           ),
         {:ok, after_key} <- decode_command_option_cursor(after_cursor),
         {:ok, %{rows: rows}} <-
           Repo.query(
             command_option_sql(kind),
             command_option_params(session_context, run_id, after_key, limit + 1)
           ) do
      choices = rows |> Enum.map(&command_option_choice(kind, &1)) |> Enum.filter(& &1)
      page_choices = Enum.take(choices, limit)

      {:ok,
       %{
         edges:
           Enum.map(page_choices, fn choice ->
             %{node: choice, cursor: KeysetCursor.encode([choice.inserted_at, choice.key])}
           end),
         has_next_page?: length(rows) > limit,
         has_previous_page?: not is_nil(after_cursor)
       }}
    else
      false -> {:error, {:invalid_field, :kind}}
      error -> error
    end
  end

  defp read_command_option_summary(session_context, run_id) do
    ["observation", "evidence_candidate", "evidence_acceptance", "waiver"]
    |> Enum.reduce_while({:ok, %{}}, fn kind, {:ok, counts} ->
      case Repo.query(
             command_option_sql(kind),
             command_option_params(
               session_context,
               run_id,
               nil,
               @child_summary_limit + 1
             )
           ) do
        {:ok, %{rows: rows}} ->
          valid_count =
            rows
            |> Enum.map(&command_option_choice(kind, &1))
            |> Enum.count(& &1)

          {:cont, {:ok, Map.put(counts, String.to_existing_atom(kind), valid_count)}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  def verification_outcome(session_context, run_id) do
    with {:ok, summary} <- Runs.get_verification_outcome_summary(session_context, run_id) do
      verification_results =
        Enum.map(summary.verification_results, &verification_result_projection/1)

      missing_evidence = Enum.map(summary.missing_evidence, &missing_evidence_projection/1)

      {:ok,
       %{
         type: "verification_outcome",
         status: verification_outcome_status(summary.run),
         run: %{
           id: summary.run.id,
           aggregate_state: summary.run.aggregate_state,
           execution_state: summary.run.execution_state,
           verification_state: summary.run.verification_state
         },
         verification_results: verification_results,
         missing_evidence: missing_evidence,
         source_watermark: outcome_watermark(summary.run, verification_results, missing_evidence)
       }}
    end
  end

  defp verification_outcome_status(run)
       when run.verification_state == "verified" or run.aggregate_state == "verified",
       do: "verified"

  defp verification_outcome_status(run)
       when run.verification_state == "failed" or run.aggregate_state == "failed",
       do: "failed"

  defp verification_outcome_status(_run), do: "awaiting_evidence"

  defp outcome_watermark(run, results, missing) do
    {run.id, run.aggregate_state, run.execution_state, run.verification_state, results, missing}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp read_evidence_candidates(session_context, run_id, limit) do
    EvidenceCandidate
    |> Ash.Query.filter(
      work_run_id == ^run_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.limit(limit)
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

  defp build_run_state(
         session_context,
         summary,
         evidence_candidates,
         verification_checks,
         command_option_summary
       ) do
    command_option_availability =
      Map.new(command_option_summary, fn {kind, count} -> {kind, count > 0} end)

    status = run_status(summary, command_option_availability)
    verification_checks_by_id = Map.new(verification_checks, &{&1.id, &1})

    command_affordances =
      run_command_affordances(
        session_context,
        status,
        summary,
        evidence_candidates,
        command_option_availability
      )

    %{
      type: "operator_run_state",
      status: status,
      allowed_next_actions: CommandAffordance.enabled_identities(command_affordances),
      command_affordances: command_affordances,
      command_options: command_options(summary, evidence_candidates, verification_checks_by_id),
      command_options_overflow:
        Enum.any?(command_option_summary, &(elem(&1, 1) > @child_summary_limit)),
      command_option_summary: command_option_summary,
      command_option_availability: command_option_availability,
      child_summary: child_summary(summary),
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
        |> Enum.map(&verification_result_projection/1),
      missing_evidence:
        summary.missing_evidence
        |> Enum.take(@child_summary_limit)
        |> Enum.map(&missing_evidence_projection/1)
    }
  end

  defp child_summary(summary) do
    counts = Map.delete(summary.child_counts, :pending_evidence_candidates)

    Map.put(
      counts,
      :has_more?,
      Enum.any?(counts, fn {_kind, count} -> count > @child_summary_limit end)
    )
  end

  defp verification_result_projection(result) do
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
  end

  defp command_option_sql("observation") do
    """
    SELECT rrc.inserted_at, rrc.id::text, vc.title, r.id::text, vc.id::text,
           vc.graph_item_id::text, NULL, NULL, NULL, NULL, NULL, NULL,
           r.execution_state, r.verification_state
    FROM run_required_checks rrc
    JOIN runs r ON r.id = rrc.run_id AND r.organization_id = $2 AND r.workspace_id = $3
    JOIN verification_checks vc ON vc.id = rrc.verification_check_id
      AND vc.organization_id = $2 AND vc.workspace_id = $3
    WHERE rrc.run_id = $1 AND rrc.organization_id = $2 AND rrc.workspace_id = $3
      AND rrc.state = 'pending'
      AND btrim(vc.title) <> ''
      AND lower(btrim(vc.title)) NOT IN ('[redacted]', '<redacted>', 'redacted', '***')
      AND NOT EXISTS (
        SELECT 1 FROM execution_observations eo
        WHERE eo.work_run_id = $1 AND eo.organization_id = $2 AND eo.workspace_id = $3
          AND eo.verification_check_id = rrc.verification_check_id
          AND eo.normalized_status = 'succeeded' AND eo.freshness_state = 'fresh'
          AND eo.trust_basis IN ('owner_attested', 'signed_provider_payload')
      )
      AND ($4::timestamp IS NULL OR (rrc.inserted_at, rrc.id) > ($4, $5::uuid))
    ORDER BY rrc.inserted_at, rrc.id
    LIMIT $6
    """
  end

  defp command_option_sql("waiver") do
    """
    SELECT rrc.inserted_at, rrc.id::text, vc.title, r.id::text, vc.id::text,
           vc.graph_item_id::text, NULL, NULL, NULL, NULL, NULL, NULL,
           r.execution_state, r.verification_state
    FROM run_required_checks rrc
    JOIN runs r ON r.id = rrc.run_id AND r.organization_id = $2 AND r.workspace_id = $3
    JOIN verification_checks vc ON vc.id = rrc.verification_check_id
      AND vc.organization_id = $2 AND vc.workspace_id = $3
    WHERE rrc.run_id = $1 AND rrc.organization_id = $2 AND rrc.workspace_id = $3
      AND rrc.state = 'pending'
      AND btrim(vc.title) <> ''
      AND lower(btrim(vc.title)) NOT IN ('[redacted]', '<redacted>', 'redacted', '***')
      AND btrim(r.execution_state) <> '' AND btrim(r.verification_state) <> ''
      AND lower(btrim(r.execution_state)) NOT IN ('[redacted]', '<redacted>', 'redacted', '***')
      AND lower(btrim(r.verification_state)) NOT IN ('[redacted]', '<redacted>', 'redacted', '***')
      AND ($4::timestamp IS NULL OR (rrc.inserted_at, rrc.id) > ($4, $5::uuid))
    ORDER BY rrc.inserted_at, rrc.id
    LIMIT $6
    """
  end

  defp command_option_sql("evidence_candidate") do
    """
    SELECT eo.inserted_at, eo.id::text, vc.title, r.id::text, vc.id::text,
           eo.graph_item_id::text, eo.source_kind, eo.source_identity,
           eo.freshness_state, eo.trust_basis, 'internal', eo.id::text,
           r.execution_state, r.verification_state
    FROM execution_observations eo
    JOIN runs r ON r.id = eo.work_run_id AND r.organization_id = $2 AND r.workspace_id = $3
    JOIN verification_checks vc ON vc.id = eo.verification_check_id
      AND vc.organization_id = $2 AND vc.workspace_id = $3
    WHERE eo.work_run_id = $1 AND eo.organization_id = $2 AND eo.workspace_id = $3
      AND eo.normalized_status = 'succeeded' AND eo.freshness_state = 'fresh'
      AND eo.trust_basis IN ('owner_attested', 'signed_provider_payload')
      AND btrim(vc.title) <> ''
      AND lower(btrim(vc.title)) NOT IN ('[redacted]', '<redacted>', 'redacted', '***')
      AND btrim(eo.source_kind) <> '' AND btrim(eo.source_identity) <> ''
      AND lower(btrim(eo.source_kind)) NOT IN ('[redacted]', '<redacted>', 'redacted', '***')
      AND lower(btrim(eo.source_identity)) NOT IN ('[redacted]', '<redacted>', 'redacted', '***')
      AND EXISTS (SELECT 1 FROM run_required_checks rrc WHERE rrc.run_id = $1
        AND rrc.organization_id = $2 AND rrc.workspace_id = $3 AND rrc.state = 'pending'
        AND rrc.verification_check_id = eo.verification_check_id)
      AND ($4::timestamp IS NULL OR (eo.inserted_at, eo.id) > ($4, $5::uuid))
    ORDER BY eo.inserted_at, eo.id
    LIMIT $6
    """
  end

  defp command_option_sql("evidence_acceptance") do
    """
    SELECT ec.inserted_at, ec.id::text, vc.title, r.id::text, vc.id::text,
           NULL, ec.source_kind, ec.source_identity, ec.freshness_state, ec.trust_basis,
           ec.sensitivity, ec.execution_observation_id::text, r.execution_state,
           r.verification_state
    FROM evidence_candidates ec
    JOIN runs r ON r.id = ec.work_run_id AND r.organization_id = $2 AND r.workspace_id = $3
    JOIN verification_checks vc ON vc.id = ec.verification_check_id
      AND vc.organization_id = $2 AND vc.workspace_id = $3
    WHERE ec.work_run_id = $1 AND ec.organization_id = $2 AND ec.workspace_id = $3
      AND ec.candidate_state = 'candidate' AND ec.freshness_state = 'fresh'
      AND ec.trust_basis IN ('owner_attested', 'signed_provider_payload')
      AND btrim(vc.title) <> ''
      AND lower(btrim(vc.title)) NOT IN ('[redacted]', '<redacted>', 'redacted', '***')
      AND EXISTS (SELECT 1 FROM run_required_checks rrc WHERE rrc.run_id = $1
        AND rrc.organization_id = $2 AND rrc.workspace_id = $3 AND rrc.state = 'pending'
        AND rrc.verification_check_id = ec.verification_check_id)
      AND ($4::timestamp IS NULL OR (ec.inserted_at, ec.id) > ($4, $5::uuid))
    ORDER BY ec.inserted_at, ec.id
    LIMIT $6
    """
  end

  defp command_option_params(session_context, run_id, after_key, limit) do
    {inserted_at, id} = after_key || {nil, nil}

    [
      Ecto.UUID.dump!(run_id),
      Ecto.UUID.dump!(session_context.organization_id),
      Ecto.UUID.dump!(session_context.workspace_id),
      inserted_at,
      if(id, do: Ecto.UUID.dump!(id), else: nil),
      limit
    ]
  end

  defp command_option_choice(kind, [
         inserted_at,
         key,
         label,
         run_id,
         check_id,
         graph_id,
         source_kind,
         source_identity,
         freshness,
         trust,
         sensitivity,
         observation_id,
         execution_state,
         verification_state
       ]) do
    base = %{
      kind: kind,
      key: key,
      label: label,
      inserted_at: NaiveDateTime.to_iso8601(inserted_at)
    }

    option =
      case kind do
        "observation" ->
          Map.put(base, :observation, %{
            key: key,
            label: label,
            run_id: run_id,
            verification_check_id: check_id,
            source_graph_item_id: graph_id,
            observation_source_kind: "human",
            observation_source_identity: "operator-console",
            freshness_state: "fresh",
            trust_basis: "owner_attested",
            default_outcome_key: "succeeded",
            outcomes: observation_outcomes()
          })

        "waiver" ->
          Map.put(base, :waiver, %{
            key: key,
            label: label,
            run_id: run_id,
            run_required_check_id: key,
            expected_execution_state: execution_state,
            expected_verification_state: verification_state,
            policy_basis: "owner_exception"
          })

        "evidence_candidate" ->
          Map.put(base, :evidence_candidate, %{
            key: key,
            label: label,
            work_run_id: run_id,
            verification_check_id: check_id,
            execution_observation_id: observation_id,
            source_kind: source_kind,
            source_identity: source_identity,
            freshness_state: freshness,
            trust_basis: trust,
            sensitivity: sensitivity
          })

        "evidence_acceptance" ->
          Map.put(base, :evidence_acceptance, %{
            key: key,
            label: label,
            evidence_candidate_id: key,
            result: "passed",
            acceptance_policy_basis: "owner_acceptance"
          })
      end

    nested = Map.get(option, String.to_existing_atom(kind))
    if complete_string_option?(nested), do: option, else: nil
  end

  defp observation_outcomes do
    [
      %{
        key: "succeeded",
        label: "Succeeded",
        observed_status: "succeeded",
        normalized_status: "succeeded"
      },
      %{key: "failed", label: "Failed", observed_status: "failed", normalized_status: "failed"}
    ]
  end

  defp decode_command_option_cursor(nil), do: {:ok, nil}

  defp decode_command_option_cursor(cursor) do
    with {:ok, [inserted_at, id]} <- KeysetCursor.decode(cursor, 2),
         {:ok, inserted_at} <- NaiveDateTime.from_iso8601(inserted_at),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, {inserted_at, id}}
    else
      _invalid -> {:error, {:invalid_field, :pagination}}
    end
  end

  defp normalize_run_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_field, :id}}
    end
  end

  defp activity_sql do
    """
    WITH activity AS (
      SELECT rrc.inserted_at, 'required_check'::text AS kind, rrc.id AS stable_id,
             COALESCE(vc.title, 'Required check') AS title, rrc.state AS status
      FROM run_required_checks rrc
      LEFT JOIN verification_checks vc
        ON vc.id = rrc.verification_check_id
       AND vc.organization_id = rrc.organization_id
       AND vc.workspace_id = rrc.workspace_id
      WHERE rrc.run_id = $1 AND rrc.organization_id = $2 AND rrc.workspace_id = $3
      UNION ALL
      SELECT inserted_at, 'observation', id, source_identity, normalized_status
      FROM execution_observations
      WHERE work_run_id = $1 AND organization_id = $2 AND workspace_id = $3
      UNION ALL
      SELECT inserted_at, 'evidence_candidate', id, claim, candidate_state
      FROM evidence_candidates
      WHERE work_run_id = $1 AND organization_id = $2 AND workspace_id = $3
      UNION ALL
      SELECT inserted_at, 'evidence_item', id, title, state
      FROM evidence_items
      WHERE work_run_id = $1 AND organization_id = $2 AND workspace_id = $3
      UNION ALL
      SELECT inserted_at, 'verification_result', id, COALESCE(policy_basis, 'Verification result'), result
      FROM verification_results
      WHERE work_run_id = $1 AND organization_id = $2 AND workspace_id = $3
      UNION ALL
      SELECT rrc.inserted_at, 'missing_evidence', rrc.verification_check_id,
             COALESCE(vc.title, 'Missing evidence'),
             CASE WHEN EXISTS (
               SELECT 1 FROM verification_results vr
               WHERE vr.work_run_id = $1 AND vr.organization_id = $2 AND vr.workspace_id = $3
                 AND vr.verification_check_id = rrc.verification_check_id
                 AND vr.result = 'failed'
             ) THEN 'failed_check' ELSE 'missing_accepted_evidence' END
      FROM run_required_checks rrc
      LEFT JOIN verification_checks vc
        ON vc.id = rrc.verification_check_id
       AND vc.organization_id = rrc.organization_id
       AND vc.workspace_id = rrc.workspace_id
      WHERE rrc.run_id = $1
        AND rrc.organization_id = $2
        AND rrc.workspace_id = $3
        AND rrc.state = 'pending'
    )
    SELECT inserted_at, kind, stable_id::text, title, status
    FROM activity
    WHERE $4::timestamp IS NULL OR (inserted_at, kind, stable_id) > ($4, $5, $6::uuid)
    ORDER BY inserted_at ASC, kind ASC, stable_id ASC
    LIMIT $7
    """
  end

  defp activity_params(session_context, run_id, nil, limit),
    do: [
      Ecto.UUID.dump!(run_id),
      Ecto.UUID.dump!(session_context.organization_id),
      Ecto.UUID.dump!(session_context.workspace_id),
      nil,
      "",
      nil,
      limit
    ]

  defp activity_params(session_context, run_id, {inserted_at, kind, id}, limit),
    do: [
      Ecto.UUID.dump!(run_id),
      Ecto.UUID.dump!(session_context.organization_id),
      Ecto.UUID.dump!(session_context.workspace_id),
      inserted_at,
      kind,
      Ecto.UUID.dump!(id),
      limit
    ]

  defp activity_edge([inserted_at, kind, id, title, status]) do
    %{
      node: %{kind: kind, stable_id: id, title: title, status: status},
      cursor: KeysetCursor.encode([NaiveDateTime.to_iso8601(inserted_at), kind, id])
    }
  end

  defp decode_activity_cursor(nil), do: {:ok, nil}

  defp decode_activity_cursor(cursor) do
    with {:ok, [inserted_at, kind, id]} <- KeysetCursor.decode(cursor, 3),
         {:ok, inserted_at} <- NaiveDateTime.from_iso8601(inserted_at),
         true <-
           kind in [
             "required_check",
             "observation",
             "evidence_candidate",
             "evidence_item",
             "verification_result",
             "missing_evidence"
           ],
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, {inserted_at, kind, id}}
    else
      _invalid -> {:error, {:invalid_field, :pagination}}
    end
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
              trust_basis: "owner_attested",
              default_outcome_key: "succeeded",
              outcomes: [
                %{
                  key: "succeeded",
                  label: "Succeeded",
                  observed_status: "succeeded",
                  normalized_status: "succeeded"
                },
                %{
                  key: "failed",
                  label: "Failed",
                  observed_status: "failed",
                  normalized_status: "failed"
                }
              ]
            }
          ]

        _missing_or_redacted ->
          []
      end
    end)
    |> Enum.filter(&complete_string_option?/1)
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
    option
    |> Map.delete(:outcomes)
    |> Enum.all?(fn {_key, value} -> usable_projection_value?(value) end) and
      valid_outcome_bundle?(option)
  end

  defp valid_outcome_bundle?(%{outcomes: outcomes, default_outcome_key: default_key}) do
    keys = Enum.map(outcomes, &Map.get(&1, :key))

    outcomes != [] and Enum.uniq(keys) == keys and default_key in keys and
      Enum.all?(outcomes, fn outcome ->
        Enum.all?(outcome, fn {_key, value} -> usable_projection_value?(value) end)
      end)
  end

  defp valid_outcome_bundle?(_option_without_outcomes), do: true

  defp usable_projection_value?(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    normalized != "" and normalized not in ["[redacted]", "<redacted>", "redacted", "***"]
  end

  defp usable_projection_value?(_value), do: false

  defp run_status(summary, _evidence_candidates)
       when summary.run.verification_state == "verified" or
              summary.run.aggregate_state == "verified" do
    "verified"
  end

  defp run_status(summary, _evidence_candidates)
       when summary.run.aggregate_state == "failed" or summary.run.verification_state == "failed" do
    "failed"
  end

  defp run_status(summary, _availability) do
    cond do
      summary.child_counts.pending_evidence_candidates > 0 and
          summary.child_counts.missing_evidence > 0 ->
        "awaiting_evidence_acceptance"

      summary.child_counts.observations > 0 and summary.child_counts.missing_evidence > 0 ->
        "awaiting_evidence"

      summary.child_counts.observations == 0 ->
        "awaiting_execution"

      true ->
        "awaiting_evidence"
    end
  end

  defp run_command_affordances(
         session_context,
         "awaiting_execution",
         summary,
         _evidence_candidates,
         availability
       ) do
    record_observation_affordance(session_context, summary, availability.observation)
    |> Kernel.++(
      waive_verification_check_affordance(session_context, summary, availability.waiver)
    )
  end

  defp run_command_affordances(
         session_context,
         "awaiting_evidence",
         summary,
         _evidence_candidates,
         availability
       ) do
    record_observation_affordance(session_context, summary, availability.observation)
    |> Kernel.++(
      create_evidence_candidate_affordance(
        session_context,
        summary,
        availability.evidence_candidate
      )
    )
    |> Kernel.++(
      waive_verification_check_affordance(session_context, summary, availability.waiver)
    )
  end

  defp run_command_affordances(
         session_context,
         "awaiting_evidence_acceptance",
         summary,
         evidence_candidates,
         availability
       ) do
    record_observation_affordance(session_context, summary, availability.observation)
    |> Kernel.++(
      accept_evidence_affordance(
        session_context,
        summary,
        evidence_candidates,
        availability.evidence_acceptance
      )
    )
    |> Kernel.++(
      waive_verification_check_affordance(session_context, summary, availability.waiver)
    )
  end

  defp run_command_affordances(
         _session_context,
         _status,
         _summary,
         _evidence_candidates,
         _availability
       ),
       do: []

  defp record_observation_affordance(_session_context, _summary, false), do: []

  defp record_observation_affordance(session_context, summary, true) do
    check_ids = checks_needing_observations(summary)

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

  defp create_evidence_candidate_affordance(_session_context, _summary, false), do: []

  defp create_evidence_candidate_affordance(session_context, summary, true) do
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

  defp accept_evidence_affordance(_session_context, _summary, _evidence_candidates, false),
    do: []

  defp accept_evidence_affordance(session_context, summary, evidence_candidates, true) do
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

  defp waive_verification_check_affordance(_session_context, _summary, false), do: []

  defp waive_verification_check_affordance(session_context, summary, true) do
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
