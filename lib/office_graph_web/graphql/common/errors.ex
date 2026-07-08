defmodule OfficeGraphWeb.GraphQL.Common.Errors do
  @moduledoc false

  def to_absinthe({:error, error}) do
    error
    |> normalize()
    |> to_absinthe_error()
  end

  def to_absinthe(error) do
    error
    |> normalize()
    |> to_absinthe_error()
  end

  defp to_absinthe_error(%{detail: detail, extensions: extensions}) do
    {:error, message: detail, extensions: extensions}
  end

  defp normalize(:forbidden) do
    %{
      detail: "The action is not authorized.",
      extensions: %{code: "forbidden"}
    }
  end

  defp normalize(%Ash.Error.Forbidden{}), do: normalize(:forbidden)

  defp normalize({:missing_proposed_change, id}) do
    %{
      detail: "A proposed change could not be found.",
      extensions: %{code: "missing_proposed_change", proposed_change_id: id}
    }
  end

  defp normalize({:invalid_proposed_change_status, id}) do
    %{
      detail: "A proposed change is no longer pending.",
      extensions: %{code: "invalid_proposed_change_status", proposed_change_id: id}
    }
  end

  defp normalize({:invalid_proposed_change, id}) do
    %{
      detail: "A proposed change failed validation.",
      extensions: %{code: "invalid_proposed_change", proposed_change_id: id}
    }
  end

  defp normalize({:invalid_proposed_change_set, reason}) do
    %{
      detail: "The proposed change set is invalid.",
      extensions: %{code: "invalid_proposed_change_set", reason: format_reason(reason)}
    }
  end

  defp normalize({:manual_intake_replay_conflict, accepted_id}) do
    %{
      detail: "Manual intake replay identity conflicts with an accepted event.",
      extensions: %{code: "manual_intake_replay_conflict", accepted_id: accepted_id}
    }
  end

  defp normalize({:missing_verification_check, id}) do
    %{
      detail: "A verification check could not be found.",
      extensions: %{code: "missing_verification_check", verification_check_id: id}
    }
  end

  defp normalize({:packet_run_flow_idempotency_conflict, flow_identity}) do
    %{
      detail: "The packet-run-verification flow identity conflicts with different input.",
      extensions: %{code: "idempotency_conflict", flow_identity: flow_identity}
    }
  end

  defp normalize({:observation_idempotency_conflict, observation_id}) do
    %{
      detail: "The observation source idempotency key conflicts with different input.",
      extensions: %{code: "idempotency_conflict", observation_id: observation_id}
    }
  end

  defp normalize({:invalid_verification_check_status, id}) do
    %{
      detail: "A verification check is no longer required.",
      extensions: %{code: "invalid_verification_check_status", verification_check_id: id}
    }
  end

  defp normalize({:packet_version_not_ready, id}) do
    %{
      detail: "The packet version is not ready for execution.",
      extensions: %{code: "packet_version_not_ready", packet_version_id: id}
    }
  end

  defp normalize({:not_found, _resource, id}) do
    %{
      detail: "A referenced record could not be found.",
      extensions: %{code: "not_found", id: id}
    }
  end

  defp normalize({:missing_normalized_intake_event, id}) do
    %{
      detail: "The operator workflow item could not be found.",
      extensions: %{code: "not_found", normalized_event_id: id}
    }
  end

  defp normalize({:missing_field, field}) do
    %{
      detail: "A required field is missing.",
      extensions: %{code: "validation_failed", field: field}
    }
  end

  defp normalize({:invalid_field, field}) do
    %{
      detail: "A field has an invalid value.",
      extensions: %{code: "validation_failed", field: field}
    }
  end

  defp normalize(error) do
    if ash_forbidden_error?(error) do
      normalize(:forbidden)
    else
      %{
        detail: "Validation failed.",
        extensions: %{code: "validation_failed"}
      }
    end
  end

  defp format_reason({kind, value}), do: %{kind: kind, value: value}
  defp format_reason(reason), do: reason

  defp ash_forbidden_error?(%Ash.Error.Forbidden{}), do: true

  defp ash_forbidden_error?(%{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &ash_forbidden_error?/1)
  end

  defp ash_forbidden_error?(_error), do: false
end
