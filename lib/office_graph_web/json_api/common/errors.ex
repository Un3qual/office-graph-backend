defmodule OfficeGraphWeb.JsonApi.Common.Errors do
  @moduledoc false

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  def render(conn, error, opts \\ []) do
    response = to_response(error, opts)

    payload =
      case Keyword.get(opts, :command) do
        nil -> %{error: response.error}
        command -> %{command: command, error: response.error}
      end

    conn
    |> put_status(response.status)
    |> json(payload)
  end

  defp to_response({:error, error}, opts), do: to_response(error, opts)

  defp to_response(:forbidden, _opts) do
    response(:forbidden, "forbidden", "The action is not authorized.")
  end

  defp to_response({:invalid_proposed_change, id}, _opts) do
    response(
      :unprocessable_entity,
      "invalid_proposed_change",
      "A proposed change failed validation.",
      %{
        proposed_change_id: id
      }
    )
  end

  defp to_response({:missing_proposed_change, id}, _opts) do
    response(
      :unprocessable_entity,
      "missing_proposed_change",
      "A proposed change could not be found.",
      %{
        proposed_change_id: id
      }
    )
  end

  defp to_response({:invalid_proposed_change_status, id}, _opts) do
    response(
      :conflict,
      "invalid_proposed_change_status",
      "A proposed change is no longer pending.",
      %{proposed_change_id: id}
    )
  end

  defp to_response({:invalid_proposed_change_set, reason}, _opts) do
    response(
      :conflict,
      "invalid_proposed_change_set",
      "The proposed change set is invalid.",
      %{
        reason: format_reason(reason)
      }
    )
  end

  defp to_response({:manual_intake_replay_conflict, accepted_id}, _opts) do
    response(
      :conflict,
      "manual_intake_replay_conflict",
      "Manual intake replay identity conflicts with an accepted event.",
      %{accepted_id: accepted_id}
    )
  end

  defp to_response({:command_idempotency_conflict, operation_id}, _opts) do
    response(
      :conflict,
      "idempotency_conflict",
      "The idempotency key conflicts with different command input.",
      %{operation_id: operation_id}
    )
  end

  defp to_response({:stale_packet_version, packet_id, current_version_id}, _opts) do
    response(
      :conflict,
      "stale_packet_version",
      "The work packet version is stale.",
      %{packet_id: packet_id, current_version_id: current_version_id}
    )
  end

  defp to_response({:stale_work_run_state, run_id, execution_state, verification_state}, _opts) do
    response(
      :conflict,
      "stale_run_state",
      "The work run state is stale.",
      %{
        run_id: run_id,
        execution_state: execution_state,
        verification_state: verification_state
      }
    )
  end

  defp to_response({:missing_verification_check, id}, _opts) do
    response(
      :unprocessable_entity,
      "missing_verification_check",
      "A verification check could not be found.",
      %{
        verification_check_id: id
      }
    )
  end

  defp to_response({:invalid_verification_check_status, id}, _opts) do
    response(
      :conflict,
      "invalid_verification_check_status",
      "A verification check is no longer required.",
      %{verification_check_id: id}
    )
  end

  defp to_response({:packet_version_not_ready, id}, _opts) do
    response(
      :unprocessable_entity,
      "packet_version_not_ready",
      "The packet version is not ready for execution.",
      %{
        packet_version_id: id
      }
    )
  end

  defp to_response({:packet_run_flow_idempotency_conflict, flow_identity}, _opts) do
    response(
      :unprocessable_entity,
      "idempotency_conflict",
      "The packet-run-verification flow identity conflicts with different input.",
      %{flow_identity: flow_identity}
    )
  end

  defp to_response({:observation_idempotency_conflict, observation_id}, _opts) do
    response(
      :conflict,
      "idempotency_conflict",
      "The observation source idempotency key conflicts with different input.",
      %{observation_id: observation_id}
    )
  end

  defp to_response({:missing_normalized_intake_event, id}, opts) do
    status = Keyword.get(opts, :missing_normalized_intake_event_status, :not_found)

    response(status, "not_found", "The operator workflow item could not be found.", %{
      normalized_event_id: id
    })
  end

  defp to_response({:not_found, _resource, id}, opts) do
    status = Keyword.get(opts, :not_found_status, :unprocessable_entity)

    response(status, "not_found", "A referenced record could not be found.", %{id: id})
  end

  defp to_response({:missing_field, field}, _opts) do
    validation_response("A required field is missing.", %{field: field})
  end

  defp to_response({:invalid_field, field}, _opts) do
    validation_response("A field has an invalid value.", %{field: field})
  end

  defp to_response(%Ash.Changeset{} = changeset, _opts) do
    response(:unprocessable_entity, "validation_failed", "Validation failed.", %{
      fields: Enum.map(changeset.errors, &format_changeset_error/1)
    })
  end

  defp to_response(error, _opts) do
    if ash_forbidden_error?(error) do
      to_response(:forbidden, [])
    else
      validation_response("Validation failed.")
    end
  end

  defp validation_response(detail, extra \\ %{}) do
    response(:unprocessable_entity, "validation_failed", detail, extra)
  end

  defp response(status, code, detail, extra \\ %{}) do
    %{status: status, error: Map.merge(%{code: code, detail: detail}, extra)}
  end

  defp format_changeset_error(%{field: field, message: message}) do
    %{field: field, message: message}
  end

  defp format_changeset_error(%{field: field}) do
    %{field: field, message: "is invalid"}
  end

  defp format_changeset_error(_error) do
    %{field: nil, message: "is invalid"}
  end

  defp format_reason({kind, value}), do: %{kind: kind, value: value}
  defp format_reason(reason), do: reason

  defp ash_forbidden_error?(%Ash.Error.Forbidden{}), do: true

  defp ash_forbidden_error?(%{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &ash_forbidden_error?/1)
  end

  defp ash_forbidden_error?(_error), do: false
end
