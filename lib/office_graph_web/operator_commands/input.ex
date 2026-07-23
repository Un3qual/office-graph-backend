defmodule OfficeGraphWeb.OperatorCommands.Input do
  @moduledoc false

  @fields %{
    bind_github_installation: [
      idempotency_key: :string,
      workspace_id: :optional_uuid,
      external_installation_id: :string,
      app_slug: :string,
      account_login: :string,
      account_type: :string,
      service_principal_email: :string,
      webhook_principal_email: :string,
      webhook_secret_reference: :string,
      app_private_key_reference: :string,
      permissions: :github_permissions
    ],
    reply_to_github_review: [
      idempotency_key: :string,
      installation_id: :uuid,
      review_comment_id: :uuid,
      body: :raw_string,
      expected_provider_version: :string
    ],
    update_github_check: [
      idempotency_key: :string,
      installation_id: :uuid,
      check_run_id: :uuid,
      status: :string,
      conclusion: :optional_string,
      details_url: :string,
      expected_provider_version: :string
    ],
    submit_manual_intake: [
      idempotency_key: :string,
      source_identity: :string,
      replay_identity: :string,
      body: :raw_string
    ],
    apply_proposed_changes: [
      idempotency_key: :string,
      normalized_event_id: :uuid,
      proposed_change_ids: {:list, :uuid}
    ],
    create_work_packet: [
      idempotency_key: :string,
      title: :string,
      objective: :string,
      context_summary: :string,
      requirements: :string,
      success_criteria: :string,
      autonomy_posture: :string,
      source_graph_item_ids: {:list, :uuid},
      verification_check_ids: {:list, :uuid}
    ],
    create_work_packet_version: [
      idempotency_key: :string,
      packet_id: :uuid,
      expected_current_version_id: :uuid,
      title: :string,
      objective: :string,
      context_summary: :string,
      requirements: :string,
      success_criteria: :string,
      autonomy_posture: :string,
      source_graph_item_ids: {:list, :uuid},
      verification_check_ids: {:list, :uuid}
    ],
    start_work_run: [
      idempotency_key: :string,
      packet_version_id: :uuid,
      source_surface: :string,
      reason: :string,
      authority_posture: :string
    ],
    record_execution_observation: [
      idempotency_key: :string,
      run_id: :uuid,
      verification_check_id: :uuid,
      source_graph_item_id: :uuid,
      observation_source_kind: :string,
      observation_source_identity: :string,
      observation_idempotency_key: :string,
      observed_status: :string,
      normalized_status: :string,
      freshness_state: :string,
      trust_basis: :string,
      observation_rationale: :string
    ],
    create_evidence_candidate: [
      idempotency_key: :string,
      work_run_id: :uuid,
      verification_check_id: :uuid,
      execution_observation_id: :uuid,
      claim: :string,
      source_kind: :string,
      source_identity: :string,
      freshness_state: :string,
      trust_basis: :string,
      sensitivity: :string
    ],
    accept_evidence: [
      idempotency_key: :string,
      evidence_candidate_id: :uuid,
      title: :string,
      body: :raw_string,
      result: :string,
      acceptance_policy_basis: :string
    ],
    waive_verification_check: [
      idempotency_key: :string,
      run_id: :uuid,
      run_required_check_id: :uuid,
      expected_execution_state: :string,
      expected_verification_state: :string,
      reason: :string,
      policy_basis: :string
    ],
    resolve_agent_approval: [
      idempotency_key: :string,
      approval_request_id: :uuid,
      expected_version: :positive_integer,
      decision: :string,
      resolution_reason: :string
    ],
    resolve_agent_context_expansion: [
      idempotency_key: :string,
      context_expansion_request_id: :uuid,
      expected_version: :positive_integer,
      decision: :string,
      resolution_reason: :string
    ],
    invoke_agent: [
      idempotency_key: :string,
      binding_id: :uuid,
      graph_item_id: :uuid,
      run_id: :uuid,
      requested_outcome: :raw_string,
      requested_capabilities: {:list, :string},
      autonomy_mode: :string
    ],
    cancel_agent_execution: [
      idempotency_key: :string,
      execution_id: :uuid,
      expected_state_version: :positive_integer
    ],
    start_run_conversation: [
      idempotency_key: :string,
      run_id: :uuid,
      graph_item_id: :uuid
    ],
    append_conversation_message: [
      idempotency_key: :string,
      conversation_id: :uuid,
      body: :raw_string,
      contribution_kind: :string,
      proposed_graph_change_id: :optional_uuid,
      domain_action_operation_id: :optional_uuid
    ]
  }

  def public_field?(field) when is_atom(field) do
    Enum.any?(@fields, fn {_command, fields} -> Keyword.has_key?(fields, field) end)
  end

  def public_field?(field) when is_binary(field) do
    Enum.any?(@fields, fn {_command, fields} ->
      Enum.any?(fields, fn {known, _type} -> Atom.to_string(known) == field end)
    end)
  end

  def public_field?(_field), do: false

  def parse(command, params) when is_map(params) do
    @fields
    |> Map.fetch!(command)
    |> Enum.reduce_while({:ok, %{}}, fn {key, type}, {:ok, parsed} ->
      case required(params, key, type) do
        {:ok, value} -> {:cont, {:ok, Map.put(parsed, key, value)}}
        :skip -> {:cont, {:ok, parsed}}
        error -> {:halt, error}
      end
    end)
  end

  defp required(params, key, :string), do: required_string(params, key, &String.trim/1)
  defp required(params, key, :raw_string), do: required_string(params, key, &Function.identity/1)

  defp required(params, key, :positive_integer) do
    case fetch(params, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      nil -> {:error, {:missing_field, key}}
      _other -> {:error, {:invalid_field, key}}
    end
  end

  defp required(params, key, :uuid) do
    with {:ok, value} <- required(params, key, :string),
         {:ok, uuid} <- Ecto.UUID.cast(value) do
      {:ok, uuid}
    else
      :error -> {:error, {:invalid_field, key}}
      error -> error
    end
  end

  defp required(params, key, :optional_uuid) do
    optional(params, key, fn value -> required(%{key => value}, key, :uuid) end)
  end

  defp required(params, key, :optional_string) do
    optional(params, key, fn value -> required(%{key => value}, key, :string) end)
  end

  defp required(params, key, :github_permissions) do
    case fetch(params, key) do
      permissions when is_list(permissions) and permissions != [] ->
        permissions
        |> Enum.reduce_while({:ok, []}, fn permission, {:ok, parsed} ->
          with true <- is_map(permission),
               {:ok, name} <- required(permission, :name, :string),
               {:ok, access_level} <- required(permission, :access_level, :string) do
            {:cont, {:ok, [%{name: name, access_level: access_level} | parsed]}}
          else
            _error -> {:halt, {:error, {:invalid_field, key}}}
          end
        end)
        |> case do
          {:ok, parsed} -> {:ok, parsed |> Enum.reverse() |> Enum.sort_by(& &1.name)}
          error -> error
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp required(params, key, {:list, type}) do
    case fetch(params, key) do
      values when is_list(values) -> parse_list(values, key, type)
      nil -> {:error, {:missing_field, key}}
      _other -> {:error, {:invalid_field, key}}
    end
  end

  defp required_string(params, key, return_value) do
    case fetch(params, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:missing_field, key}}
          _nonblank -> {:ok, return_value.(value)}
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp parse_list(values, key, type) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, parsed} ->
      case required(%{key => value}, key, type) do
        {:ok, cast} -> {:cont, {:ok, [cast | parsed]}}
        _error -> {:halt, {:error, {:invalid_field, key}}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp fetch(params, key) do
    string_key = to_string(key)

    cond do
      Map.has_key?(params, key) -> Map.fetch!(params, key)
      Map.has_key?(params, string_key) -> Map.fetch!(params, string_key)
      true -> nil
    end
  end

  defp optional(params, key, parser) do
    if has_key?(params, key) do
      case fetch(params, key) do
        nil -> {:ok, nil}
        value -> parser.(value)
      end
    else
      :skip
    end
  end

  defp has_key?(params, key),
    do: Map.has_key?(params, key) or Map.has_key?(params, to_string(key))
end
