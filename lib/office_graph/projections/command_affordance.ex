defmodule OfficeGraph.Projections.CommandAffordance do
  @moduledoc false

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

  def packet_required_fields, do: @packet_required_fields

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
      target_ids: Keyword.get(opts, :target_ids, []),
      trace_links: Keyword.get(opts, :trace_links, []),
      decision_links: Keyword.get(opts, :decision_links, [])
    }
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
