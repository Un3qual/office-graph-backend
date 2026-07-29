defmodule OfficeGraph.Projections.RunState do
  @moduledoc false

  alias OfficeGraph.Projections.CommandAffordance
  alias OfficeGraph.Projections.KeysetCursor
  alias OfficeGraph.Projections.RunState.Activity
  alias OfficeGraph.Projections.RunState.CommandOptions
  alias OfficeGraph.Authorization
  alias OfficeGraph.Runs
  alias OfficeGraph.WorkGraph.EvidenceCandidate

  require Ash.Query

  @child_summary_limit 20

  def operator_run_state(session_context, run_id) do
    with {:ok, summary} <-
           Runs.get_projection_summary(session_context, run_id, @child_summary_limit),
         {:ok, evidence_candidates} <-
           read_evidence_candidates(session_context, summary.run.id, @child_summary_limit),
         {:ok, command_option_insights} <-
           CommandOptions.summary(
             session_context,
             summary.run,
             command_option_counts(summary),
             @child_summary_limit
           ) do
      {:ok,
       build_run_state(
         session_context,
         summary,
         evidence_candidates,
         command_option_insights
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
         {:ok, run_id} <- normalize_run_id(run_id),
         {:ok, run} <- Runs.get_projection_run(session_context, run_id),
         {:ok, after_key} <- decode_activity_cursor(after_cursor),
         {:ok, activities} <- Activity.page(session_context, run, after_key, limit) do
      page_activities = Enum.take(activities, limit)

      {:ok,
       %{
         edges: Enum.map(page_activities, &activity_edge/1),
         has_next_page?: length(activities) > limit,
         has_previous_page?: not is_nil(after_cursor)
       }}
    end
  end

  def command_option_page(session_context, run_id, kind, opts) do
    limit = Keyword.fetch!(opts, :limit)
    after_cursor = Keyword.get(opts, :after_cursor)

    with true <- kind in CommandOptions.kinds(),
         {:ok, run_id} <- normalize_run_id(run_id),
         {:ok, run} <- Runs.get_projection_run(session_context, run_id),
         {:ok, after_key} <- decode_command_option_cursor(after_cursor),
         {:ok, choices} <-
           CommandOptions.page(session_context, run, kind, after_key, limit) do
      page_choices = Enum.take(choices, limit)

      {:ok,
       %{
         edges:
           Enum.map(page_choices, fn choice ->
             %{node: choice, cursor: KeysetCursor.encode([choice.inserted_at, choice.key])}
           end),
         has_next_page?: length(choices) > limit,
         has_previous_page?: not is_nil(after_cursor)
       }}
    else
      false -> {:error, {:invalid_field, :kind}}
      error -> error
    end
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

  defp build_run_state(
         session_context,
         summary,
         evidence_candidates,
         command_option_insights
       ) do
    command_option_summary =
      Map.new(command_option_insights, fn {kind, insight} -> {kind, insight.count} end)

    command_option_choices =
      Map.new(command_option_insights, fn {kind, insight} -> {kind, insight.option} end)

    command_option_availability =
      Map.new(command_option_choices, fn {kind, option} -> {kind, not is_nil(option)} end)

    status = run_status(summary, command_option_availability)

    command_affordances =
      run_command_affordances(
        session_context,
        status,
        summary,
        evidence_candidates,
        command_option_choices
      )

    %{
      type: "operator_run_state",
      run_id: summary.run.id,
      status: status,
      allowed_next_actions: CommandAffordance.enabled_identities(command_affordances),
      command_affordances: command_affordances,
      command_options: command_options(command_option_insights),
      command_options_overflow:
        Enum.any?(command_option_summary, &(elem(&1, 1) > @child_summary_limit)),
      command_option_summary: command_option_summary,
      command_option_availability: command_option_availability,
      child_summary: child_summary(summary),
      missing_evidence:
        summary.missing_evidence
        |> Enum.take(@child_summary_limit)
        |> Enum.map(&missing_evidence_projection/1)
    }
    |> with_source_watermark()
  end

  defp child_summary(summary) do
    counts =
      Map.drop(summary.child_counts, [
        :pending_evidence_candidates,
        :observation_command_options,
        :evidence_candidate_command_options,
        :evidence_acceptance_command_options,
        :waiver_command_options
      ])

    Map.put(
      counts,
      :has_more?,
      Enum.any?(counts, fn {_kind, count} -> count > @child_summary_limit end)
    )
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

  defp activity_edge(activity) do
    %{
      node: Map.take(activity, [:kind, :stable_id, :title, :status]),
      cursor:
        KeysetCursor.encode([
          activity_timestamp(activity.inserted_at),
          activity.kind,
          activity.stable_id
        ])
    }
  end

  defp activity_timestamp(%DateTime{} = inserted_at) do
    inserted_at
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
  end

  defp activity_timestamp(%NaiveDateTime{} = inserted_at),
    do: NaiveDateTime.to_iso8601(inserted_at)

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
             "missing_evidence",
             "agent_execution",
             "agent_context",
             "agent_approval",
             "agent_context_expansion",
             "agent_tool_request",
             "agent_proposal",
             "conversation_message"
           ],
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, {inserted_at, kind, id}}
    else
      _invalid -> {:error, {:invalid_field, :pagination}}
    end
  end

  defp command_options(command_option_insights) do
    Map.new(command_option_insights, fn {kind, insight} -> {kind, insight.options} end)
  end

  defp command_option_counts(summary) do
    %{
      observation: summary.child_counts.observation_command_options,
      evidence_candidate: summary.child_counts.evidence_candidate_command_options,
      evidence_acceptance: summary.child_counts.evidence_acceptance_command_options,
      waiver:
        if(command_option_state_usable?(summary.run),
          do: summary.child_counts.waiver_command_options,
          else: 0
        )
    }
  end

  defp command_option_state_usable?(run) do
    Enum.all?([run.execution_state, run.verification_state], fn value ->
      if is_binary(value) do
        normalized = value |> String.trim() |> String.downcase()
        normalized != "" and normalized not in ["[redacted]", "<redacted>", "redacted", "***"]
      else
        false
      end
    end)
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

  defp record_observation_affordance(_session_context, _summary, nil), do: []

  defp record_observation_affordance(session_context, _summary, option) do
    if CommandAffordance.authorized?(session_context, :execution_observation_record) do
      [
        CommandAffordance.enabled(
          "record_execution_observation",
          "Record execution observations for this run.",
          required_fields: CommandAffordance.observation_required_fields(),
          input_defaults: [CommandAffordance.input_default("run_id", option.run_id)],
          target_ids: [
            CommandAffordance.target_id("work_run", option.run_id),
            CommandAffordance.target_id("verification_check", option.verification_check_id)
          ]
        )
      ]
    else
      [CommandAffordance.policy_restricted("record_execution_observation")]
    end
  end

  defp create_evidence_candidate_affordance(_session_context, _summary, nil), do: []

  defp create_evidence_candidate_affordance(session_context, _summary, option) do
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
          input_defaults: candidate_input_defaults(option),
          target_ids: [
            CommandAffordance.target_id("work_run", option.work_run_id),
            CommandAffordance.target_id("verification_check", option.verification_check_id),
            CommandAffordance.target_id(
              "execution_observation",
              option.execution_observation_id
            )
          ]
        )
      ]
    else
      [CommandAffordance.policy_restricted("create_evidence_candidate")]
    end
  end

  defp accept_evidence_affordance(_session_context, _summary, _evidence_candidates, nil),
    do: []

  defp accept_evidence_affordance(session_context, _summary, _evidence_candidates, option) do
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
          target_ids: [
            CommandAffordance.target_id("work_run", option.work_run_id),
            CommandAffordance.target_id("verification_check", option.verification_check_id),
            CommandAffordance.target_id("evidence_candidate", option.evidence_candidate_id)
          ]
        )
      ]
    else
      [CommandAffordance.policy_restricted("accept_evidence")]
    end
  end

  defp candidate_input_defaults(option) do
    [
      CommandAffordance.input_default("work_run_id", option.work_run_id),
      CommandAffordance.input_default(
        "verification_check_id",
        [option.verification_check_id]
      ),
      CommandAffordance.input_default(
        "execution_observation_id",
        [option.execution_observation_id]
      ),
      CommandAffordance.input_default("sensitivity", option.sensitivity)
    ]
  end

  defp waive_verification_check_affordance(_session_context, _summary, nil), do: []

  defp waive_verification_check_affordance(session_context, _summary, option) do
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
          input_defaults: waiver_input_defaults(option),
          target_ids: [
            CommandAffordance.target_id("work_run", option.run_id),
            CommandAffordance.target_id("run_required_check", option.run_required_check_id)
          ]
        )
      ]
    else
      []
    end
  end

  defp waiver_input_defaults(option) do
    [
      CommandAffordance.input_default("run_id", option.run_id),
      CommandAffordance.input_default(
        "run_required_check_id",
        [option.run_required_check_id]
      ),
      CommandAffordance.input_default(
        "expected_execution_state",
        option.expected_execution_state
      ),
      CommandAffordance.input_default(
        "expected_verification_state",
        option.expected_verification_state
      )
    ]
  end

  defp missing_evidence_projection(%{
         verification_check_id: verification_check_id,
         reason: reason
       }) do
    %{verification_check_id: verification_check_id, reason: reason}
  end

  defp with_source_watermark(projection) do
    watermark =
      projection
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    Map.put(projection, :source_watermark, watermark)
  end
end
