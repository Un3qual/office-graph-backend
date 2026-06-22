defmodule OfficeGraph.ApiSupport do
  @moduledoc """
  Public boundary for shared API context loading and response support.
  """

  use Boundary,
    deps: [
      OfficeGraph.Foundation,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph

  def submit_manual_intake(params) do
    with {:ok, source_identity} <- required_string(params, :source_identity),
         {:ok, replay_identity} <- required_string(params, :replay_identity),
         {:ok, body} <- required_string(params, :body),
         {:ok, bootstrap} <- bootstrap_local_api_owner(),
         {:ok, operation} <- Operations.start_operation(bootstrap.session, :manual_intake_submit) do
      Integrations.submit_manual_intake(bootstrap.session, operation, %{
        source_identity: source_identity,
        replay_identity: replay_identity,
        body: body
      })
    end
  end

  def apply_proposed_changes(params) do
    with {:ok, ids} <- optional_id_list(params, :ids),
         :ok <- validate_apply_id_set(ids),
         {:ok, bootstrap} <- bootstrap_local_api_owner(),
         {:ok, proposed_changes} <- ProposedChanges.get_many(bootstrap.session, ids),
         {:ok, operation} <- Operations.start_operation(bootstrap.session, :proposed_change_apply) do
      ProposedChanges.apply_all(bootstrap.session, operation, proposed_changes)
    end
  end

  def complete_verification(params) do
    with {:ok, verification_check_id} <- required_id(params, :verification_check_id),
         {:ok, title} <- required_string(params, :title),
         {:ok, body} <- required_string(params, :body),
         {:ok, bootstrap} <- bootstrap_local_api_owner(),
         {:ok, verification_check} <-
           WorkGraph.get_verification_check(bootstrap.session, verification_check_id),
         {:ok, operation} <- Operations.start_operation(bootstrap.session, :verification_complete) do
      Verification.complete_with_evidence(bootstrap.session, operation, verification_check, %{
        title: title,
        body: body,
        artifact_uri: value(params, :artifact_uri)
      })
    end
  end

  defp bootstrap_local_api_owner do
    if Application.get_env(:office_graph, :allow_local_api_owner_bootstrap, false) do
      Foundation.bootstrap_local_owner([])
    else
      {:error, :forbidden}
    end
  end

  defp required_id(params, key) do
    case value(params, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, {:missing_field, key}}
        else
          cast_id(value, key)
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp required_string(params, key) do
    case value(params, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, {:missing_field, key}}
        else
          {:ok, value}
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp validate_apply_id_set([]) do
    {:error, {:invalid_proposed_change_set, {:missing_change_type, "create_signal"}}}
  end

  defp validate_apply_id_set(_ids), do: :ok

  defp optional_id_list(params, key) do
    case value(params, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        cast_id_list(values, key)

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp cast_id_list(values, key) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, ids} ->
      case cast_id(value, key) do
        {:ok, id} -> {:cont, {:ok, [id | ids]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp cast_id(value, key) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_field, key}}
    end
  end

  defp cast_id(_value, key), do: {:error, {:invalid_field, key}}

  defp value(params, key) do
    params[key] || params[to_string(key)]
  end
end
