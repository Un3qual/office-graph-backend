defmodule OfficeGraph.EnterpriseIdentity.Actions.ApplyDirectoryEvent do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.EnterpriseIdentity.{
    Directory,
    ActionSupport,
    DirectoryApplyResult,
    DirectoryGroup,
    DirectoryMembership,
    DirectoryUser
  }

  alias OfficeGraph.{Identity, Operations}

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    event = input.arguments.event

    result =
      with {:ok, event_order} <-
             event_order(event.provider_event_id, input.arguments.provider_received_at),
           {:ok, directory} <- locked_directory(input.arguments.directory_id),
           {:ok, operation} <- Operations.lock_operation(input.arguments.operation_id),
           :ok <- validate_operation(directory, operation) do
        apply_event(directory, event, event_order)
      end

    case result do
      {:ok, _result} = success -> success
      {:error, error} -> ActionSupport.rollback(Directory, error)
    end
  end

  defp apply_event(directory, %{resource_kind: :user, data: data}, event_order),
    do: apply_user(directory, data, event_order)

  defp apply_event(directory, %{resource_kind: :group, data: data}, event_order),
    do: apply_group(directory, data, event_order)

  defp apply_event(directory, %{resource_kind: :membership, data: data}, event_order),
    do: apply_membership(directory, data, event_order)

  defp apply_event(_directory, _event, _event_order), do: {:error, :unsupported_event}

  defp apply_user(directory, data, event_order) do
    with {:ok, data} <- normalize_user_data(data),
         {:ok, current} <- locked_directory_user(directory.id, data.provider_user_id) do
      if stale?(current, data.provider_updated_at, event_order) do
        DirectoryApplyResult.stale(current)
      else
        synchronize_user(directory, current, data, event_order)
      end
    end
  end

  defp synchronize_user(directory, current, %{status: "active"} = data, event_order) do
    case reconcile_active_user(directory, current, data) do
      {:ok, principal, link, principal_origin} ->
        attrs =
          user_attrs(data)
          |> Map.merge(event_order)
          |> Map.merge(%{
            status: "active",
            review_reason: nil,
            principal_id: principal.id,
            external_identity_link_id: link.id,
            principal_origin: principal_origin
          })

        current
        |> persist_user(directory.id, attrs)
        |> map_resource_result(&DirectoryApplyResult.applied/1)

      {:review, reason} ->
        attrs =
          user_attrs(data)
          |> Map.merge(event_order)
          |> Map.merge(%{
            status: "review_required",
            review_reason: reason,
            principal_id: current && current.principal_id,
            external_identity_link_id: current && current.external_identity_link_id,
            principal_origin: current && current.principal_origin
          })

        with :ok <- maybe_disable_review_identity_basis(directory, current, data) do
          current
          |> persist_user(directory.id, attrs)
          |> map_resource_result(&DirectoryApplyResult.review_required/1)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp synchronize_user(directory, nil, data, event_order) do
    data
    |> user_attrs()
    |> Map.merge(event_order)
    |> Map.merge(%{
      status: data.status,
      review_reason: nil,
      principal_id: nil,
      external_identity_link_id: nil,
      principal_origin: nil
    })
    |> then(&persist_user(nil, directory.id, &1))
    |> map_resource_result(&DirectoryApplyResult.applied/1)
  end

  defp synchronize_user(directory, current, data, event_order) do
    with :ok <- disable_workos_identity_basis(directory, current, data.provider_updated_at) do
      data
      |> user_attrs()
      |> Map.merge(event_order)
      |> Map.merge(%{
        status: data.status,
        review_reason: nil,
        principal_id: current.principal_id,
        external_identity_link_id: current.external_identity_link_id,
        principal_origin: current.principal_origin
      })
      |> then(&persist_user(current, directory.id, &1))
      |> map_resource_result(&DirectoryApplyResult.applied/1)
    end
  end

  defp reconcile_active_user(directory, current, data) do
    if idp_identity_changed?(current, data) do
      {:review, "provider_subject_conflict"}
    else
      case Identity.reconcile_directory_identity(%{
             provider_tenant: directory.connection.provider_organization_id,
             subject: data.provider_user_id,
             provider_identity_id: data.idp_id,
             verified_email: data.email,
             current_principal_id: current && current.principal_id,
             current_principal_origin: current && current.principal_origin
           }) do
        {:ok,
         %{
           principal: principal,
           external_identity_link: link,
           principal_origin: principal_origin
         }} ->
          {:ok, principal, link, principal_origin}

        result ->
          result
      end
    end
  end

  defp idp_identity_changed?(
         %DirectoryUser{idp_id: current_idp_id},
         %{idp_id: incoming_idp_id}
       )
       when is_binary(current_idp_id),
       do: current_idp_id != incoming_idp_id

  defp idp_identity_changed?(_current, _data), do: false

  defp normalize_user_data(
         %{
           provider_user_id: provider_user_id,
           email: email,
           status: status,
           provider_updated_at: %DateTime{} = provider_updated_at
         } = data
       )
       when is_binary(provider_user_id) and is_binary(email) and
              status in ["active", "suspended", "deleted"] do
    email = email |> String.trim() |> String.downcase()

    if provider_user_id != "" and email != "" do
      {:ok,
       %{
         provider_user_id: provider_user_id,
         idp_id: optional_string(data[:idp_id]),
         email: email,
         first_name: optional_string(data[:first_name]),
         last_name: optional_string(data[:last_name]),
         status: status,
         provider_updated_at: provider_updated_at
       }}
    else
      {:error, :invalid_directory_event}
    end
  end

  defp normalize_user_data(_data), do: {:error, :invalid_directory_event}

  defp user_attrs(data) do
    Map.take(data, [
      :provider_user_id,
      :idp_id,
      :email,
      :first_name,
      :last_name,
      :provider_updated_at
    ])
  end

  defp persist_user(nil, directory_id, attrs) do
    DirectoryUser
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :directory_id, directory_id))
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp persist_user(%DirectoryUser{} = user, _directory_id, attrs) do
    user
    |> Ash.Changeset.for_update(:synchronize, Map.drop(attrs, [:provider_user_id]))
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp apply_group(directory, data, event_order) do
    with {:ok, data} <- normalize_group_data(data),
         {:ok, current} <- locked_directory_group(directory.id, data.provider_group_id) do
      if stale?(current, data.provider_updated_at, event_order) do
        DirectoryApplyResult.stale(current)
      else
        current
        |> persist_group(directory.id, Map.merge(data, event_order))
        |> map_resource_result(&DirectoryApplyResult.applied/1)
      end
    end
  end

  defp normalize_group_data(%{
         provider_group_id: provider_group_id,
         name: name,
         status: status,
         provider_updated_at: %DateTime{} = provider_updated_at
       })
       when is_binary(provider_group_id) and is_binary(name) and
              status in ["active", "deleted"] do
    provider_group_id = String.trim(provider_group_id)
    name = String.trim(name)

    if provider_group_id != "" and name != "" do
      {:ok,
       %{
         provider_group_id: provider_group_id,
         name: name,
         status: status,
         provider_updated_at: provider_updated_at
       }}
    else
      {:error, :invalid_directory_event}
    end
  end

  defp normalize_group_data(_data), do: {:error, :invalid_directory_event}

  defp persist_group(nil, directory_id, attrs) do
    DirectoryGroup
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :directory_id, directory_id))
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp persist_group(%DirectoryGroup{} = group, _directory_id, attrs) do
    group
    |> Ash.Changeset.for_update(:synchronize, Map.drop(attrs, [:provider_group_id]))
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp apply_membership(directory, data, event_order) do
    with {:ok, data} <- normalize_membership_data(data),
         {:ok, user} <-
           membership_directory_user(
             directory.id,
             data.provider_user_id,
             data.status
           ),
         {:ok, group} <-
           membership_directory_group(
             directory.id,
             data.provider_group_id,
             data.status
           ),
         {:ok, current} <- locked_latest_membership(user.id, group.id) do
      if stale?(current, data.provider_updated_at, event_order) do
        DirectoryApplyResult.stale(current)
      else
        cond do
          data.status == "active" and active_membership?(current) ->
            update_membership(current, data, event_order)

          data.status == "active" ->
            create_membership(user.id, group.id, data, event_order)

          is_nil(current) ->
            {:error, :directory_dependency_missing}

          true ->
            update_membership(current, data, event_order)
        end
        |> map_resource_result(&DirectoryApplyResult.applied/1)
      end
    end
  end

  defp normalize_membership_data(%{
         provider_group_id: provider_group_id,
         provider_user_id: provider_user_id,
         status: status,
         provider_updated_at: %DateTime{} = provider_updated_at
       })
       when is_binary(provider_group_id) and is_binary(provider_user_id) and
              status in ["active", "removed"] do
    {:ok,
     %{
       provider_group_id: provider_group_id,
       provider_user_id: provider_user_id,
       status: status,
       provider_updated_at: provider_updated_at
     }}
  end

  defp normalize_membership_data(_data), do: {:error, :invalid_directory_event}

  defp create_membership(user_id, group_id, data, event_order) do
    DirectoryMembership
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(event_order, %{
        directory_user_id: user_id,
        directory_group_id: group_id,
        status: data.status,
        provider_updated_at: data.provider_updated_at,
        removed_at: removed_at(data)
      })
    )
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp update_membership(membership, data, event_order) do
    membership
    |> Ash.Changeset.for_update(
      :set_lifecycle,
      Map.merge(event_order, %{
        status: data.status,
        provider_updated_at: data.provider_updated_at,
        removed_at: removed_at(data)
      })
    )
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp removed_at(%{status: "removed", provider_updated_at: timestamp}), do: timestamp
  defp removed_at(_active), do: nil

  defp active_membership?(%DirectoryMembership{
         status: "active",
         active_identity_slot: "active"
       }),
       do: true

  defp active_membership?(_membership), do: false

  defp disable_workos_identity_basis(directory, user, disabled_at) do
    with {:ok, principal_created_by_directory} <-
           principal_created_by_directory?(user.principal_id) do
      Identity.deprovision_directory_identity(%{
        external_identity_link_id: user.external_identity_link_id,
        principal_id: user.principal_id,
        principal_created_by_directory: principal_created_by_directory,
        provider_tenant: directory.connection.provider_organization_id,
        provider_identity_id: user.idp_id,
        disabled_at: disabled_at
      })
    end
  end

  defp principal_created_by_directory?(nil), do: {:ok, false}

  defp principal_created_by_directory?(principal_id) do
    DirectoryUser
    |> Ash.Query.filter(principal_id == ^principal_id and principal_origin == "created")
    |> Ash.exists(authorize?: false)
  end

  defp maybe_disable_review_identity_basis(_directory, nil, _data), do: :ok

  defp maybe_disable_review_identity_basis(directory, user, data),
    do: disable_workos_identity_basis(directory, user, data.provider_updated_at)

  defp locked_directory(directory_id) do
    Directory
    |> Ash.Query.filter(id == ^directory_id and status == "active")
    |> Ash.Query.load(:connection)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Directory{connection: %{status: "active"}} = directory} -> {:ok, directory}
      {:ok, _missing_or_inactive} -> {:error, :unknown_directory}
      {:error, _reason} = error -> error
    end
  end

  defp validate_operation(directory, operation) do
    connection = directory.connection

    if operation.organization_id == connection.organization_id and
         operation.workspace_id == connection.workspace_id do
      Operations.validate_system_operation(operation, :provider_webhook_receive)
    else
      {:error, :forbidden}
    end
  end

  defp locked_directory_user(directory_id, provider_user_id) do
    DirectoryUser
    |> Ash.Query.filter(directory_id == ^directory_id and provider_user_id == ^provider_user_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp locked_directory_group(directory_id, provider_group_id) do
    DirectoryGroup
    |> Ash.Query.filter(directory_id == ^directory_id and provider_group_id == ^provider_group_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp active_directory_user(directory_id, provider_user_id) do
    DirectoryUser
    |> Ash.Query.filter(
      directory_id == ^directory_id and provider_user_id == ^provider_user_id and
        status == "active"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> required_dependency()
  end

  defp active_directory_group(directory_id, provider_group_id) do
    DirectoryGroup
    |> Ash.Query.filter(
      directory_id == ^directory_id and provider_group_id == ^provider_group_id and
        status == "active"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> required_dependency()
  end

  defp membership_directory_user(directory_id, provider_user_id, "active"),
    do: active_directory_user(directory_id, provider_user_id)

  defp membership_directory_user(directory_id, provider_user_id, "removed") do
    directory_id
    |> locked_directory_user(provider_user_id)
    |> required_dependency()
  end

  defp membership_directory_group(directory_id, provider_group_id, "active"),
    do: active_directory_group(directory_id, provider_group_id)

  defp membership_directory_group(directory_id, provider_group_id, "removed") do
    directory_id
    |> locked_directory_group(provider_group_id)
    |> required_dependency()
  end

  defp required_dependency({:ok, nil}), do: {:error, :directory_dependency_missing}
  defp required_dependency(result), do: result

  defp locked_latest_membership(user_id, group_id) do
    DirectoryMembership
    |> Ash.Query.filter(directory_user_id == ^user_id and directory_group_id == ^group_id)
    |> Ash.Query.sort(
      provider_updated_at: :desc,
      provider_received_at: :desc_nils_last,
      provider_event_id: :desc_nils_last,
      id: :desc
    )
    |> Ash.Query.limit(1)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp stale?(nil, _incoming, _event_order), do: false

  defp stale?(%{provider_event_id: provider_event_id}, _incoming, %{
         provider_event_id: provider_event_id
       })
       when is_binary(provider_event_id),
       do: true

  defp stale?(%{provider_updated_at: current} = record, incoming, event_order) do
    case DateTime.compare(incoming, current) do
      :lt -> true
      :gt -> false
      :eq -> stale_equal_time?(record, event_order)
    end
  end

  defp stale_equal_time?(%{provider_received_at: nil}, _event_order), do: false

  defp stale_equal_time?(record, event_order) do
    case DateTime.compare(event_order.provider_received_at, record.provider_received_at) do
      :lt -> true
      :gt -> false
      :eq -> event_order.provider_event_id <= (record.provider_event_id || "")
    end
  end

  defp event_order(provider_event_id, %DateTime{} = provider_received_at)
       when is_binary(provider_event_id) do
    case String.trim(provider_event_id) do
      "" ->
        {:error, :invalid_directory_event}

      provider_event_id ->
        {:ok,
         %{
           provider_event_id: provider_event_id,
           provider_received_at: provider_received_at
         }}
    end
  end

  defp event_order(_provider_event_id, _provider_received_at),
    do: {:error, :invalid_directory_event}

  defp optional_string(nil), do: nil

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> String.slice(normalized, 0, 255)
    end
  end

  defp optional_string(_value), do: nil

  defp map_resource_result({:ok, resource}, mapper), do: mapper.(resource)
  defp map_resource_result({:error, _reason} = error, _mapper), do: error

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}
end
