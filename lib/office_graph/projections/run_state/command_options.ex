defmodule OfficeGraph.Projections.RunState.CommandOptions do
  @moduledoc false

  alias OfficeGraph.Runs.{ExecutionObservation, RunRequiredCheck}
  alias OfficeGraph.WorkGraph.EvidenceCandidate

  require Ash.Query

  @kinds ~w(observation evidence_candidate evidence_acceptance waiver)
  @redacted_values ["[redacted]", "<redacted>", "redacted", "***"]

  def kinds, do: @kinds

  def page(session_context, run, kind, after_key, limit) when kind in @kinds do
    if kind == "waiver" and not waiver_state_usable?(run) do
      {:ok, []}
    else
      read_page(session_context, run, kind, after_key, limit)
    end
  end

  def summary(session_context, run, counts, limit) do
    Enum.reduce_while(@kinds, {:ok, %{}}, fn kind, {:ok, insights} ->
      kind_atom = String.to_existing_atom(kind)
      count = Map.fetch!(counts, kind_atom)

      if count == 0 do
        insight = %{count: 0, option: nil, options: []}
        {:cont, {:ok, Map.put(insights, kind_atom, insight)}}
      else
        case page(session_context, run, kind, nil, limit) do
          {:ok, choices} ->
            options =
              choices
              |> Enum.take(limit)
              |> Enum.map(&Map.fetch!(&1, kind_atom))

            insight = %{count: count, option: List.first(options), options: options}
            {:cont, {:ok, Map.put(insights, kind_atom, insight)}}

          {:error, error} ->
            {:halt, {:error, error}}
        end
      end
    end)
  end

  defp read_page(session_context, run, kind, after_key, limit) do
    with {:ok, choices} <-
           session_context
           |> choice_query(run, kind)
           |> apply_cursor(after_key)
           |> Ash.Query.sort(inserted_at: :asc, id: :asc)
           |> Ash.Query.limit(limit + 1)
           |> Ash.read(actor: session_context) do
      {:ok, Enum.map(choices, &choice(kind, run, &1))}
    end
  end

  defp choice_query(session_context, run, "observation") do
    RunRequiredCheck
    |> scoped_required_checks(session_context, run.id)
    |> Ash.Query.filter(
      state == "pending" and
        string_trim(verification_check.title) != "" and
        string_downcase(string_trim(verification_check.title)) not in ^@redacted_values and
        not exists(
          OfficeGraph.Runs.ExecutionObservation,
          work_run_id == parent(run_id) and
            organization_id == parent(organization_id) and
            workspace_id == parent(workspace_id) and
            verification_check_id == parent(verification_check_id) and
            normalized_status == "succeeded" and freshness_state == "fresh" and
            trust_basis in ["owner_attested", "signed_provider_payload"]
        )
    )
  end

  defp choice_query(session_context, run, "waiver") do
    RunRequiredCheck
    |> scoped_required_checks(session_context, run.id)
    |> Ash.Query.filter(
      state == "pending" and
        string_trim(verification_check.title) != "" and
        string_downcase(string_trim(verification_check.title)) not in ^@redacted_values
    )
  end

  defp choice_query(session_context, run, "evidence_candidate") do
    ExecutionObservation
    |> Ash.Query.filter(
      work_run_id == ^run.id and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        normalized_status == "succeeded" and freshness_state == "fresh" and
        trust_basis in ["owner_attested", "signed_provider_payload"] and
        string_trim(verification_check.title) != "" and
        string_downcase(string_trim(verification_check.title)) not in ^@redacted_values and
        string_trim(source_kind) != "" and string_trim(source_identity) != "" and
        string_downcase(string_trim(source_kind)) not in ^@redacted_values and
        string_downcase(string_trim(source_identity)) not in ^@redacted_values and
        exists(
          OfficeGraph.Runs.RunRequiredCheck,
          run_id == parent(work_run_id) and
            organization_id == parent(organization_id) and
            workspace_id == parent(workspace_id) and
            verification_check_id == parent(verification_check_id) and state == "pending"
        )
    )
    |> Ash.Query.load(:verification_check)
  end

  defp choice_query(session_context, run, "evidence_acceptance") do
    EvidenceCandidate
    |> Ash.Query.filter(
      work_run_id == ^run.id and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        candidate_state == "candidate" and freshness_state == "fresh" and
        trust_basis in ["owner_attested", "signed_provider_payload"] and
        string_trim(verification_check.title) != "" and
        string_downcase(string_trim(verification_check.title)) not in ^@redacted_values and
        exists(
          OfficeGraph.Runs.RunRequiredCheck,
          run_id == parent(work_run_id) and
            organization_id == parent(organization_id) and
            workspace_id == parent(workspace_id) and
            verification_check_id == parent(verification_check_id) and state == "pending"
        )
    )
    |> Ash.Query.load(:verification_check)
  end

  defp scoped_required_checks(query, session_context, run_id) do
    query
    |> Ash.Query.filter(
      run_id == ^run_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.load(:verification_check)
  end

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, {inserted_at, id}) do
    inserted_at = DateTime.from_naive!(inserted_at, "Etc/UTC")

    Ash.Query.filter(
      query,
      inserted_at > ^inserted_at or (inserted_at == ^inserted_at and id > ^id)
    )
  end

  defp choice("observation", run, required_check) do
    base_choice("observation", required_check, %{
      key: required_check.id,
      label: required_check.verification_check.title,
      run_id: run.id,
      verification_check_id: required_check.verification_check_id,
      source_graph_item_id: required_check.verification_check.graph_item_id,
      observation_source_kind: "human",
      observation_source_identity: "operator-console",
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      default_outcome_key: "succeeded",
      outcomes: observation_outcomes()
    })
  end

  defp choice("waiver", run, required_check) do
    base_choice("waiver", required_check, %{
      key: required_check.id,
      label: required_check.verification_check.title,
      run_id: run.id,
      run_required_check_id: required_check.id,
      expected_execution_state: run.execution_state,
      expected_verification_state: run.verification_state,
      policy_basis: "owner_exception"
    })
  end

  defp choice("evidence_candidate", run, observation) do
    base_choice("evidence_candidate", observation, %{
      key: observation.id,
      label: observation.verification_check.title,
      work_run_id: run.id,
      verification_check_id: observation.verification_check_id,
      execution_observation_id: observation.id,
      source_kind: observation.source_kind,
      source_identity: observation.source_identity,
      freshness_state: observation.freshness_state,
      trust_basis: observation.trust_basis,
      sensitivity: "internal"
    })
  end

  defp choice("evidence_acceptance", run, candidate) do
    base_choice("evidence_acceptance", candidate, %{
      key: candidate.id,
      label: candidate.verification_check.title,
      evidence_candidate_id: candidate.id,
      work_run_id: run.id,
      verification_check_id: candidate.verification_check_id,
      result: "passed",
      acceptance_policy_basis: "owner_acceptance"
    })
  end

  defp base_choice(kind, record, option) do
    %{
      kind: kind,
      key: record.id,
      label: record.verification_check.title,
      inserted_at: cursor_timestamp(record.inserted_at)
    }
    |> Map.put(String.to_existing_atom(kind), option)
  end

  defp cursor_timestamp(%DateTime{} = inserted_at) do
    inserted_at
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
  end

  defp cursor_timestamp(%NaiveDateTime{} = inserted_at),
    do: NaiveDateTime.to_iso8601(inserted_at)

  defp waiver_state_usable?(run) do
    usable_value?(run.execution_state) and usable_value?(run.verification_state)
  end

  defp usable_value?(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    normalized != "" and normalized not in @redacted_values
  end

  defp usable_value?(_value), do: false

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
end
