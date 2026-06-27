defmodule OfficeGraph.WorkPackets.Changes.ValidateCurrentVersion do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.WorkPackets.WorkPacketVersion

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    current_version_id = Ash.Changeset.get_attribute(changeset, :current_version_id)

    with {:ok, packet_id, organization_id, workspace_id} <- packet_scope(changeset),
         {:ok, version} <- fetch_current_version(current_version_id),
         :ok <- validate_version_owner(version, packet_id, organization_id, workspace_id) do
      changeset
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)
    end
  end

  defp packet_scope(%{
         data: %{id: packet_id, organization_id: organization_id, workspace_id: workspace_id}
       })
       when not is_nil(packet_id) and not is_nil(organization_id) and not is_nil(workspace_id) do
    {:ok, packet_id, organization_id, workspace_id}
  end

  defp packet_scope(_changeset) do
    {:error, :current_version_id, "current_version_id must be set on a persisted packet"}
  end

  defp fetch_current_version(nil) do
    {:error, :current_version_id, "current_version_id must reference a packet version"}
  end

  defp fetch_current_version(current_version_id) do
    WorkPacketVersion
    |> Ash.Query.filter(id == ^current_version_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:error, :current_version_id, "current_version_id must reference a packet version"}

      {:ok, version} ->
        {:ok, version}

      {:error, error} ->
        {:error, :current_version_id, "current_version_id lookup failed: #{format_error(error)}"}
    end
  end

  defp validate_version_owner(
         %{
           work_packet_id: packet_id,
           organization_id: organization_id,
           workspace_id: workspace_id
         },
         packet_id,
         organization_id,
         workspace_id
       ) do
    :ok
  end

  defp validate_version_owner(_version, _packet_id, _organization_id, _workspace_id) do
    {:error, :current_version_id,
     "current_version_id must reference a version owned by the packet"}
  end

  defp format_error(%{__exception__: true} = error), do: Exception.message(error)
  defp format_error(error), do: inspect(error)
end
