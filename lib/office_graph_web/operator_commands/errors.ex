defmodule OfficeGraphWeb.OperatorCommands.Errors do
  @moduledoc false

  @safe_token ~r/\A[a-z0-9][a-z0-9:_-]{0,159}\z/
  @internal_segments [
    "ash",
    "adapter",
    "connection",
    "database",
    "dbconnection",
    "ecto",
    "error",
    "exception",
    "postgres",
    "postgrex",
    "query",
    "runtime",
    "sql"
  ]
  @internal_prefixes ["ash", "dbconnection", "ecto", "postgres", "postgrex"]
  @safe_domain_tokens [
    "create_review_finding",
    "create_signal",
    "create_task",
    "create_verification_check"
  ]
  @sql_leading_tokens [
    "alter",
    "analyze",
    "begin",
    "call",
    "comment",
    "commit",
    "copy",
    "create",
    "delete",
    "drop",
    "execute",
    "explain",
    "from",
    "grant",
    "insert",
    "join",
    "lock",
    "merge",
    "prepare",
    "reindex",
    "release",
    "revoke",
    "rollback",
    "savepoint",
    "select",
    "set",
    "show",
    "truncate",
    "union",
    "update",
    "vacuum",
    "values",
    "where",
    "with"
  ]

  @type classification :: %{
          category: :authorization | :conflict | :not_found | :validation,
          code: String.t(),
          detail: String.t(),
          fields: [map()],
          metadata: map()
        }

  @spec classify(term()) :: classification()
  def classify({:error, error}), do: classify(error)

  def classify(:forbidden) do
    result(:authorization, "forbidden", "The action is not authorized.")
  end

  def classify(%Ash.Error.Forbidden{}), do: classify(:forbidden)

  def classify({:missing_proposed_change, id}) do
    result(:validation, "missing_proposed_change", "A proposed change could not be found.", %{
      proposed_change_id: id
    })
  end

  def classify({:invalid_proposed_change_status, id}) do
    result(:conflict, "invalid_proposed_change_status", "A proposed change is no longer pending.",
      proposed_change_id: id
    )
  end

  def classify({:invalid_proposed_change, id}) do
    result(:validation, "invalid_proposed_change", "A proposed change failed validation.",
      proposed_change_id: id
    )
  end

  def classify({:invalid_proposed_change_set, reason}) do
    result(:conflict, "invalid_proposed_change_set", "The proposed change set is invalid.",
      reason: reason
    )
  end

  def classify({:invalid_proposed_change_replay, _reason}) do
    result(
      :validation,
      "invalid_proposed_change_replay",
      "The applied proposal result is unavailable."
    )
  end

  def classify({:manual_intake_replay_conflict, accepted_id}) do
    result(
      :conflict,
      "manual_intake_replay_conflict",
      "Manual intake replay identity conflicts with an accepted event.",
      accepted_id: accepted_id
    )
  end

  def classify({:command_idempotency_conflict, operation_id}) do
    result(
      :conflict,
      "idempotency_conflict",
      "The idempotency key conflicts with different command input.",
      operation_id: operation_id
    )
  end

  def classify({:stale_packet_version, packet_id, current_version_id}) do
    result(:conflict, "stale_packet_version", "The work packet version is stale.",
      packet_id: packet_id,
      current_version_id: current_version_id
    )
  end

  def classify({:active_work_run, packet_version_id, run_id}) do
    result(:conflict, "active_work_run", "The packet version already has an active work run.",
      packet_version_id: packet_version_id,
      run_id: run_id
    )
  end

  def classify({:stale_work_run_state, run_id, execution_state, verification_state}) do
    result(:conflict, "stale_run_state", "The work run state is stale.",
      run_id: run_id,
      execution_state: execution_state,
      verification_state: verification_state
    )
  end

  def classify({:missing_verification_check, id}) do
    result(:validation, "missing_verification_check", "A verification check could not be found.",
      verification_check_id: id
    )
  end

  def classify({:invalid_evidence_result, evidence_result}) do
    result(:validation, "invalid_evidence_result", "The evidence result is not supported.",
      evidence_result: evidence_result
    )
  end

  def classify({:observation_idempotency_conflict, observation_id}) do
    result(
      :conflict,
      "idempotency_conflict",
      "The observation source idempotency key conflicts with different input.",
      observation_id: observation_id
    )
  end

  def classify({:invalid_verification_check_status, id}) do
    result(
      :conflict,
      "invalid_verification_check_status",
      "A verification check is no longer required.",
      verification_check_id: id
    )
  end

  def classify({:packet_version_not_ready, id}) do
    result(
      :validation,
      "packet_version_not_ready",
      "The packet version is not ready for execution.",
      packet_version_id: id
    )
  end

  def classify({:evidence_candidate_already_accepted, id}) do
    result(
      :conflict,
      "evidence_candidate_already_accepted",
      "The evidence candidate was already accepted.",
      evidence_candidate_id: id
    )
  end

  def classify({:verification_result_slot_conflict, run_id, verification_check_id}) do
    result(
      :conflict,
      "verification_result_slot_conflict",
      "The verification result slot was already completed.",
      run_id: run_id,
      verification_check_id: verification_check_id
    )
  end

  def classify({:not_found, _resource, id}) do
    result(:not_found, "not_found", "A referenced record could not be found.", id: id)
  end

  def classify({:missing_normalized_intake_event, id}) do
    result(:not_found, "not_found", "The operator workflow item could not be found.",
      normalized_event_id: id
    )
  end

  def classify({:missing_field, field}) do
    field_error("A required field is missing.", field)
  end

  def classify({:invalid_field, field}) do
    field_error("A field has an invalid value.", field)
  end

  def classify(%Ash.Changeset{} = changeset) do
    fields = changeset_fields(changeset.errors)
    result(:validation, "validation_failed", "Validation failed.", %{}, fields)
  end

  def classify(error) do
    if ash_forbidden_error?(error) do
      classify(:forbidden)
    else
      result(:validation, "validation_failed", "Validation failed.")
    end
  end

  defp field_error(detail, field) do
    field = sanitize_field(field)

    result(:validation, "validation_failed", detail, %{field: field}, [
      %{field: field, message: detail}
    ])
  end

  defp changeset_field(%{field: field}) do
    %{field: sanitize_field(field), message: "is invalid"}
  end

  defp changeset_field(_error), do: %{field: nil, message: "is invalid"}

  defp changeset_fields([]), do: []

  defp changeset_fields([error | errors]) do
    [changeset_field(error) | changeset_fields(errors)]
  end

  defp changeset_fields(_malformed), do: []

  defp result(category, code, detail, metadata \\ %{}, fields \\ []) do
    %{
      category: category,
      code: code,
      detail: detail,
      fields: fields,
      metadata: sanitize_metadata(metadata)
    }
  end

  defp sanitize_metadata(metadata) do
    Map.new(metadata, fn {key, value} -> {key, sanitize(value)} end)
  end

  defp sanitize({kind, value}) when is_atom(kind) do
    case sanitize_atom(kind) do
      "internal" -> %{kind: "internal", value: "invalid"}
      safe_kind -> %{kind: safe_kind, value: sanitize(value)}
    end
  end

  defp sanitize(nil), do: nil
  defp sanitize(value) when is_boolean(value) or is_number(value), do: value
  defp sanitize(value) when is_atom(value), do: sanitize_atom(value)
  defp sanitize(value) when is_list(value), do: sanitize_list(value)

  defp sanitize(%{__exception__: true}), do: "invalid"

  defp sanitize(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> sanitize_map()
  end

  defp sanitize(value) when is_map(value) and not is_struct(value) do
    sanitize_map(value)
  end

  defp sanitize(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&sanitize/1)

  defp sanitize(value) when is_binary(value) do
    if safe_token?(value) do
      value
    else
      "invalid"
    end
  end

  defp sanitize(_value), do: "invalid"

  defp sanitize_list([]), do: []
  defp sanitize_list([head | tail]), do: [sanitize(head) | sanitize_list_tail(tail)]

  defp sanitize_list_tail([]), do: []
  defp sanitize_list_tail([head | tail]), do: [sanitize(head) | sanitize_list_tail(tail)]
  defp sanitize_list_tail(tail), do: [sanitize(tail)]

  defp sanitize_map(value) do
    Map.new(value, fn {key, nested} ->
      case sanitize_key(key) do
        "invalid" -> {"invalid", "invalid"}
        safe_key -> {safe_key, sanitize(nested)}
      end
    end)
  end

  defp sanitize_key(key) when is_atom(key), do: key |> Atom.to_string() |> sanitize_key()

  defp sanitize_key(key) when is_binary(key) do
    if safe_token?(key), do: key, else: "invalid"
  end

  defp sanitize_key(key) when is_number(key), do: to_string(key)
  defp sanitize_key(_key), do: "invalid"

  defp sanitize_atom(atom) do
    value = Atom.to_string(atom)

    if safe_token?(value), do: value, else: "internal"
  end

  defp sanitize_field(field) when is_atom(field),
    do: field |> Atom.to_string() |> sanitize_field()

  defp sanitize_field(field) when is_binary(field) do
    if safe_token?(field), do: field, else: "invalid"
  end

  defp sanitize_field(_field), do: "invalid"

  defp safe_token?(value) do
    byte_size(value) <= 160 and String.valid?(value) and Regex.match?(@safe_token, value) and
      safe_token_semantics?(value)
  end

  defp safe_token_semantics?(value) do
    segments = String.split(value, [":", "_", "-"], trim: true)
    first = List.first(segments)

    value in @safe_domain_tokens or
      (first not in @sql_leading_tokens and
         Enum.all?(segments, &(&1 not in @internal_segments)) and
         Enum.all?(@internal_prefixes, &(not String.starts_with?(value, &1))) and
         not String.ends_with?(value, "error"))
  end

  defp ash_forbidden_error?(%Ash.Error.Forbidden{}), do: true

  defp ash_forbidden_error?(%{errors: errors}), do: any_ash_forbidden_error?(errors)

  defp ash_forbidden_error?(_error), do: false

  defp any_ash_forbidden_error?([]), do: false

  defp any_ash_forbidden_error?([error | errors]) do
    ash_forbidden_error?(error) or any_ash_forbidden_error?(errors)
  end

  defp any_ash_forbidden_error?(_malformed), do: false
end
