defmodule OfficeGraph.Projections.CommandAffordance do
  @moduledoc false

  alias OfficeGraph.Authorization

  @packet_required_fields [
    "title",
    "objective",
    "context_summary",
    "requirements",
    "success_criteria",
    "autonomy_posture",
    "source_graph_item_ids",
    "verification_check_ids"
  ]

  @observation_required_fields [
    "observation_source_kind",
    "observation_source_identity",
    "observation_idempotency_key",
    "observed_status",
    "normalized_status",
    "freshness_state",
    "trust_basis",
    "verification_check_id",
    "source_graph_item_id",
    "observation_rationale"
  ]

  def packet_required_fields, do: @packet_required_fields
  def observation_required_fields, do: @observation_required_fields

  def enabled(identity, safe_explanation, opts \\ []) do
    new(identity, "enabled", safe_explanation, opts)
  end

  def disabled(identity, safe_explanation, opts \\ []) do
    new(identity, "disabled", safe_explanation, opts)
  end

  def hidden(identity, safe_explanation, opts \\ []) do
    new(identity, "hidden", safe_explanation, opts)
  end

  def redacted(identity, safe_explanation, opts \\ []) do
    new(identity, "redacted", safe_explanation, opts)
  end

  def new(identity, state, safe_explanation, opts) do
    %{
      identity: identity,
      state: state,
      reason_codes: Keyword.get(opts, :reason_codes, []),
      blocker_reasons: Keyword.get(opts, :blocker_reasons, []),
      safe_explanation: safe_explanation,
      required_fields: Keyword.get(opts, :required_fields, []),
      input_defaults: Keyword.get(opts, :input_defaults, []),
      target_ids: Keyword.get(opts, :target_ids, []),
      trace_links: Keyword.get(opts, :trace_links, []),
      decision_links: Keyword.get(opts, :decision_links, [])
    }
  end

  def policy_restricted(identity, opts \\ []) do
    hidden(
      identity,
      "This command is not available for the current operator.",
      Keyword.merge(
        [
          reason_codes: ["policy_restricted"],
          blocker_reasons: ["policy_restricted"],
          target_ids: [],
          trace_links: [],
          decision_links: []
        ],
        opts
      )
    )
  end

  def authorized?(session_context, capability) do
    Authorization.authorize_projection(session_context, capability,
      organization_id: session_context.organization_id
    ) == :ok
  end

  def input_default(field, values) when is_list(values) do
    %{field: field, value: nil, values: values}
  end

  def input_default(field, nil) do
    %{field: field, value: nil, values: []}
  end

  def input_default(field, value) do
    %{field: field, value: to_string(value), values: []}
  end

  def enabled_identities(command_affordances) do
    command_affordances
    |> Enum.filter(&(&1.state == "enabled"))
    |> Enum.map(& &1.identity)
  end

  def target_id(_type, nil), do: nil
  def target_id(type, id), do: %{type: type, id: id}

  def compact_target_ids(target_ids), do: Enum.reject(target_ids, &is_nil/1)
end
