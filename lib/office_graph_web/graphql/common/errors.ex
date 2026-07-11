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

  defp normalize({:invalid_proposed_change_replay, _reason}) do
    %{
      detail: "The applied proposal result is unavailable.",
      extensions: %{code: "invalid_proposed_change_replay"}
    }
  end

  defp normalize({:manual_intake_replay_conflict, accepted_id}) do
    %{
      detail: "Manual intake replay identity conflicts with an accepted event.",
      extensions: %{code: "manual_intake_replay_conflict", accepted_id: accepted_id}
    }
  end

  defp normalize({:command_idempotency_conflict, operation_id}) do
    %{
      detail: "The idempotency key conflicts with different command input.",
      extensions: %{code: "idempotency_conflict", operation_id: operation_id}
    }
  end

  defp normalize({:stale_packet_version, packet_id, current_version_id}) do
    %{
      detail: "The work packet version is stale.",
      extensions: %{
        code: "stale_packet_version",
        packet_id: packet_id,
        current_version_id: current_version_id
      }
    }
  end

  defp normalize({:stale_work_run_state, run_id, execution_state, verification_state}) do
    %{
      detail: "The work run state is stale.",
      extensions: %{
        code: "stale_run_state",
        run_id: run_id,
        execution_state: execution_state,
        verification_state: verification_state
      }
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

  defp normalize(
         {:source_graph_item_check_mismatch, source_graph_item_id, verification_check_id,
          expected_graph_item_id}
       ) do
    %{
      detail: "The source graph item does not match the verification check.",
      extensions: %{
        code: "source_graph_item_check_mismatch",
        source_graph_item_id: source_graph_item_id,
        verification_check_id: verification_check_id,
        expected_graph_item_id: expected_graph_item_id
      }
    }
  end

  defp normalize({:invalid_packet_run_input, reason}) do
    %{
      detail: "The packet-run-verification input is not ready for execution.",
      extensions: %{code: "packet_run_input_not_ready", reason: reason}
    }
  end

  defp normalize({:invalid_evidence_result, result}) do
    %{
      detail: "The evidence result is not supported for packet-run verification.",
      extensions: %{code: "invalid_evidence_result", evidence_result: result}
    }
  end

  defp normalize({:invalid_packet_run_evidence_input, reason}) do
    %{
      detail: "The packet-run-verification evidence input is invalid.",
      extensions: %{code: "invalid_packet_run_evidence_input", reason: reason}
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

  defp format_reason({kind, value}) when is_atom(kind) do
    %{kind: safe_atom(kind), value: format_reason(value)}
  end

  defp format_reason(nil), do: nil
  defp format_reason(reason) when is_boolean(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: safe_atom(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_number(reason), do: reason
  defp format_reason(reason) when is_list(reason), do: Enum.map(reason, &format_reason/1)

  defp format_reason(reason) when is_map(reason) and not is_struct(reason) do
    Map.new(reason, fn {key, value} -> {to_string(key), format_reason(value)} end)
  end

  defp format_reason(_reason), do: "invalid"

  defp safe_atom(atom) do
    atom
    |> Atom.to_string()
    |> case do
      "Elixir." <> _module -> "internal"
      value -> value
    end
  end

  defp ash_forbidden_error?(%Ash.Error.Forbidden{}), do: true

  defp ash_forbidden_error?(%{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &ash_forbidden_error?/1)
  end

  defp ash_forbidden_error?(_error), do: false
end
