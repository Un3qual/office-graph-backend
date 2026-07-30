defmodule OfficeGraph.EnterpriseIdentity.AuthorizationFacts do
  @moduledoc false

  @behaviour OfficeGraph.Authorization.ExternalRoleFacts

  alias OfficeGraph.EnterpriseIdentity.{
    DirectoryMembership,
    ExternalGroupRoleMapping
  }

  require Ash.Query

  @impl true
  def login_scopes(principal_id) when is_binary(principal_id) do
    with {:ok, group_ids} <- active_group_ids(principal_id),
         {:ok, mappings} <- active_mappings(group_ids) do
      scopes =
        mappings
        |> Enum.filter(&is_binary(&1.workspace_id))
        |> Enum.map(&%{organization_id: &1.organization_id, workspace_id: &1.workspace_id})
        |> Enum.uniq()

      {:ok, scopes}
    end
  end

  def login_scopes(_principal_id), do: {:ok, []}

  @impl true
  def role_ids(principal_id, organization_id, workspace_id, candidate_role_ids)
      when is_binary(principal_id) and is_binary(organization_id) and
             (is_nil(workspace_id) or is_binary(workspace_id)) and
             is_list(candidate_role_ids) do
    with {:ok, group_ids} <- active_group_ids(principal_id),
         {:ok, mappings} <-
           active_mappings(
             group_ids,
             organization_id,
             workspace_id,
             candidate_role_ids
           ) do
      {:ok, mappings |> Enum.map(& &1.role_id) |> Enum.uniq()}
    end
  end

  def role_ids(_principal_id, _organization_id, _workspace_id, _candidate_role_ids),
    do: {:ok, []}

  defp active_group_ids(principal_id) do
    DirectoryMembership
    |> Ash.Query.filter(
      status == "active" and
        directory_user.principal_id == ^principal_id and
        directory_user.status == "active" and
        directory_user.directory.status == "active" and
        directory_user.directory.connection.status == "active" and
        directory_group.status == "active" and
        directory_group.directory.status == "active" and
        directory_group.directory.connection.status == "active"
    )
    |> Ash.Query.select([:directory_group_id])
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, memberships} ->
        {:ok, memberships |> Enum.map(& &1.directory_group_id) |> Enum.uniq()}

      {:error, _storage_error} ->
        {:error, :enterprise_identity_storage_unavailable}
    end
  end

  defp active_mappings([]), do: {:ok, []}

  defp active_mappings(group_ids) do
    ExternalGroupRoleMapping
    |> Ash.Query.filter(
      directory_group_id in ^group_ids and status == "active" and
        directory_group.status == "active" and
        directory_group.directory.status == "active" and
        directory_group.directory.connection.status == "active" and
        role.organization_id == organization_id
    )
    |> Ash.read(authorize?: false)
    |> normalize_read()
  end

  defp active_mappings([], _organization_id, _workspace_id, _candidate_role_ids),
    do: {:ok, []}

  defp active_mappings(group_ids, organization_id, nil, candidate_role_ids) do
    ExternalGroupRoleMapping
    |> Ash.Query.filter(
      directory_group_id in ^group_ids and status == "active" and
        organization_id == ^organization_id and is_nil(workspace_id) and
        role_id in ^candidate_role_ids and role.organization_id == ^organization_id and
        directory_group.status == "active" and
        directory_group.directory.status == "active" and
        directory_group.directory.connection.status == "active"
    )
    |> Ash.Query.select([:role_id])
    |> Ash.read(authorize?: false)
    |> normalize_read()
  end

  defp active_mappings(group_ids, organization_id, workspace_id, candidate_role_ids) do
    ExternalGroupRoleMapping
    |> Ash.Query.filter(
      directory_group_id in ^group_ids and status == "active" and
        organization_id == ^organization_id and workspace_id == ^workspace_id and
        role_id in ^candidate_role_ids and role.organization_id == ^organization_id and
        directory_group.status == "active" and
        directory_group.directory.status == "active" and
        directory_group.directory.connection.status == "active"
    )
    |> Ash.Query.select([:role_id])
    |> Ash.read(authorize?: false)
    |> normalize_read()
  end

  defp normalize_read({:ok, records}), do: {:ok, records}

  defp normalize_read({:error, _storage_error}),
    do: {:error, :enterprise_identity_storage_unavailable}
end
