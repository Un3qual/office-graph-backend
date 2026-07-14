defmodule OfficeGraphWeb.OperatorCommands.Errors do
  @moduledoc false

  alias OfficeGraphWeb.OperatorCommands.Input

  @uuid_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @uuid_metadata_keys [
    :accepted_id,
    :current_version_id,
    :evidence_candidate_id,
    :id,
    :normalized_event_id,
    :observation_id,
    :operation_id,
    :packet_id,
    :packet_version_id,
    :proposed_change_id,
    :run_id,
    :verification_check_id
  ]
  @change_types [
    "create_review_finding",
    "create_signal",
    "create_task",
    "create_verification_check"
  ]
  @execution_states ["completed", "failed", "pending", "running"]
  @verification_states ["failed", "missing_evidence", "pending", "unverified", "verified"]
  @evidence_results ["failed", "passed", "waived"]
  @simple_reason_tokens [
    "existing_normalized_event_changes",
    "invalid_apply_input",
    "missing_normalized_event_id"
  ]
  @uuid_reason_kinds [
    "normalized_event_mismatch",
    "normalized_event_not_accepted",
    "normalized_event_operation_mismatch"
  ]
  @change_type_reason_kinds ["duplicate_change_type", "missing_change_type"]
  @opaque_reason_kinds ["normalized_event_lookup_failed", "unexpected_change_type"]
  @auxiliary_fields [
    "after_cursor",
    "first",
    "id",
    "occurred_at",
    "pagination",
    "session_context",
    "subject_version"
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

  def classify({:authorization, _safe_code}), do: classify(:forbidden)

  def classify({:stale_version, :provider_version}) do
    result(:conflict, "stale_provider_version", "The provider object version is stale.")
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

  def classify(%Ash.Error.Invalid{} = error) do
    fields = validation_fields(error)
    result(:validation, "validation_failed", "Validation failed.", %{}, fields)
  end

  def classify(%Ash.Changeset{} = changeset) do
    fields = validation_fields(changeset)
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

  defp validation_fields(%Ash.Error.Invalid{errors: errors, changeset: changeset}) do
    case validation_fields(errors) do
      [] -> validation_fields(changeset)
      fields -> fields
    end
  end

  defp validation_fields(%Ash.Changeset{errors: errors}), do: validation_fields(errors)
  defp validation_fields(%{errors: errors}), do: validation_fields(errors)

  defp validation_fields(%{field: field}) do
    [validation_field(field)]
  end

  defp validation_fields(%{fields: fields}), do: validation_field_list(fields)

  defp validation_fields(errors) when is_list(errors) do
    errors
    |> validation_fields_list([])
    |> Enum.reverse()
  end

  defp validation_fields(_malformed), do: []

  defp validation_fields_list([], fields), do: fields

  defp validation_fields_list([error | errors], fields) do
    validation_fields_list(errors, Enum.reverse(validation_fields(error), fields))
  end

  defp validation_fields_list(_malformed_tail, fields), do: fields

  defp validation_field(field) do
    %{field: sanitize_field(field), message: "is invalid"}
  end

  defp validation_field_list([]), do: []

  defp validation_field_list([field | fields]) do
    [validation_field(field) | validation_field_list(fields)]
  end

  defp validation_field_list(_malformed), do: []

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
    Enum.reduce(metadata, %{}, fn {key, value}, sanitized ->
      case sanitize_metadata_entry(key, value) do
        {:ok, safe_value} -> Map.put(sanitized, key, safe_value)
        :error -> Map.put(sanitized, :invalid, "invalid")
      end
    end)
  end

  defp sanitize_metadata_entry(key, value) when key in @uuid_metadata_keys do
    {:ok, sanitize_uuid(value)}
  end

  defp sanitize_metadata_entry(:execution_state, value) do
    {:ok, sanitize_enum(value, @execution_states)}
  end

  defp sanitize_metadata_entry(:verification_state, value) do
    {:ok, sanitize_enum(value, @verification_states)}
  end

  defp sanitize_metadata_entry(:evidence_result, value) do
    {:ok, sanitize_enum(value, @evidence_results)}
  end

  defp sanitize_metadata_entry(:reason, value), do: {:ok, sanitize_reason(value)}
  defp sanitize_metadata_entry(:field, value), do: {:ok, sanitize_field(value)}
  defp sanitize_metadata_entry(_key, _value), do: :error

  defp sanitize_uuid(value) when is_binary(value) do
    if Regex.match?(@uuid_pattern, value), do: value, else: "invalid"
  end

  defp sanitize_uuid(_value), do: "invalid"

  defp sanitize_enum(value, allowed) when is_atom(value) do
    sanitize_enum(Atom.to_string(value), allowed)
  end

  defp sanitize_enum(value, allowed) when is_binary(value) do
    if value in allowed, do: value, else: "invalid"
  end

  defp sanitize_enum(_value, _allowed), do: "invalid"

  defp sanitize_reason(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> sanitize_simple_reason()
  end

  defp sanitize_reason(value) when is_binary(value), do: sanitize_simple_reason(value)

  defp sanitize_reason({kind, value}) when is_atom(kind) do
    kind
    |> Atom.to_string()
    |> sanitize_reason_pair(value)
  end

  defp sanitize_reason(_value), do: "invalid"

  defp sanitize_simple_reason(value) do
    if value in @simple_reason_tokens, do: value, else: "invalid"
  end

  defp sanitize_reason_pair(kind, value) when kind in @uuid_reason_kinds do
    %{kind: kind, value: sanitize_uuid(value)}
  end

  defp sanitize_reason_pair("mixed_normalized_event_ids" = kind, value) do
    %{kind: kind, value: sanitize_uuid_list(value)}
  end

  defp sanitize_reason_pair(kind, value) when kind in @change_type_reason_kinds do
    %{kind: kind, value: sanitize_enum(value, @change_types)}
  end

  defp sanitize_reason_pair(kind, _value) when kind in @opaque_reason_kinds do
    %{kind: kind, value: "invalid"}
  end

  defp sanitize_reason_pair(_kind, _value), do: "invalid"

  defp sanitize_uuid_list(value), do: sanitize_uuid_list(value, [])

  defp sanitize_uuid_list([], sanitized), do: Enum.reverse(sanitized)

  defp sanitize_uuid_list([value | values], sanitized) do
    case sanitize_uuid(value) do
      "invalid" -> "invalid"
      uuid -> sanitize_uuid_list(values, [uuid | sanitized])
    end
  end

  defp sanitize_uuid_list(_malformed, _sanitized), do: "invalid"

  defp sanitize_field(field) when is_atom(field), do: sanitize_field(Atom.to_string(field))

  defp sanitize_field(field) when is_binary(field) do
    if Input.public_field?(field) or field in @auxiliary_fields, do: field, else: "invalid"
  end

  defp sanitize_field(_field), do: "invalid"

  defp ash_forbidden_error?(%Ash.Error.Forbidden{}), do: true

  defp ash_forbidden_error?(%{errors: errors}), do: any_ash_forbidden_error?(errors)

  defp ash_forbidden_error?(_error), do: false

  defp any_ash_forbidden_error?([]), do: false

  defp any_ash_forbidden_error?([error | errors]) do
    ash_forbidden_error?(error) or any_ash_forbidden_error?(errors)
  end

  defp any_ash_forbidden_error?(_malformed), do: false
end
