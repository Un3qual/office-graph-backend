defmodule OfficeGraph.Runs.Changes.ValidateRunStartContract do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.WorkPackets

  alias OfficeGraph.WorkPackets.{
    WorkPacketRequiredCheck,
    WorkPacketSourceReference,
    WorkPacketVersion
  }

  alias OfficeGraph.WorkGraph.VerificationCheck

  require Ash.Query

  @allowed_packet_autonomy_postures MapSet.new(["human_supervised"])

  @impl true
  def change(changeset, _opts, _context) do
    work_packet_id = Ash.Changeset.get_attribute(changeset, :work_packet_id)
    work_packet_version_id = Ash.Changeset.get_attribute(changeset, :work_packet_version_id)
    authority_posture = Ash.Changeset.get_attribute(changeset, :authority_posture)
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)

    with {:ok, packet_version} <-
           fetch_scoped_packet_version(work_packet_version_id, organization_id, workspace_id) do
      changeset
      |> validate_packet_version_belongs(packet_version, work_packet_id)
      |> validate_packet_version_ready(packet_version)
      |> validate_authority_posture(packet_version, authority_posture)
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)
    end
  end

  defp fetch_scoped_packet_version(nil, _organization_id, _workspace_id) do
    {:error, :work_packet_version_id,
     "work_packet_version_id must reference a ready packet version"}
  end

  defp fetch_scoped_packet_version(_version_id, nil, _workspace_id) do
    {:error, :organization_id, "target organization_id and workspace_id are required"}
  end

  defp fetch_scoped_packet_version(_version_id, _organization_id, nil) do
    {:error, :workspace_id, "target organization_id and workspace_id are required"}
  end

  defp fetch_scoped_packet_version(version_id, organization_id, workspace_id) do
    WorkPacketVersion
    |> Ash.Query.filter(id == ^version_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id} = packet_version} ->
        {:ok, packet_version}

      {:ok, _missing_or_cross_scope} ->
        {:error, :work_packet_version_id,
         "work_packet_version_id must reference a ready packet version"}

      {:error, error} ->
        {:error, :work_packet_version_id,
         "work_packet_version_id lookup failed: #{format_lookup_error(error)}"}
    end
  end

  defp validate_packet_version_belongs(
         changeset,
         %{work_packet_id: work_packet_id},
         work_packet_id
       ) do
    changeset
  end

  defp validate_packet_version_belongs(changeset, _packet_version, _work_packet_id) do
    Ash.Changeset.add_error(changeset,
      field: :work_packet_version_id,
      message: "work_packet_version_id must belong to work_packet_id"
    )
  end

  defp validate_packet_version_ready(changeset, packet_version) do
    if ready_for_run?(packet_version) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :work_packet_version_id,
        message: "work_packet_version_id must reference a ready packet version"
      )
    end
  end

  defp ready_for_run?(%{lifecycle_state: "ready"} = packet_version) do
    with true <- present?(packet_version.objective),
         true <- present?(packet_version.context_summary),
         true <- present?(packet_version.requirements),
         true <- present?(packet_version.success_criteria),
         true <-
           MapSet.member?(@allowed_packet_autonomy_postures, packet_version.autonomy_posture),
         {:ok, source_graph_item_ids} <- packet_source_graph_item_ids(packet_version),
         true <- source_graph_item_ids != [],
         {:ok, verification_checks} <- packet_required_checks(packet_version),
         true <- verification_checks != [],
         [] <- WorkPackets.mismatched_source_check_ids(source_graph_item_ids, verification_checks) do
      true
    else
      _not_ready -> false
    end
  end

  defp ready_for_run?(_packet_version), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp packet_source_graph_item_ids(packet_version) do
    WorkPacketSourceReference
    |> Ash.Query.filter(
      work_packet_version_id == ^packet_version.id and
        organization_id == ^packet_version.organization_id and
        workspace_id == ^packet_version.workspace_id
    )
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, source_references} -> {:ok, Enum.map(source_references, & &1.graph_item_id)}
      {:error, error} -> {:error, error}
    end
  end

  defp packet_required_checks(packet_version) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(
      work_packet_version_id == ^packet_version.id and
        organization_id == ^packet_version.organization_id and
        workspace_id == ^packet_version.workspace_id
    )
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, required_checks} ->
        verification_check_ids = Enum.map(required_checks, & &1.verification_check_id)

        with true <- verification_check_ids != [],
             {:ok, verification_checks} <-
               read_verification_checks(packet_version, verification_check_ids),
             true <- length(verification_checks) == length(Enum.uniq(verification_check_ids)) do
          {:ok, verification_checks}
        else
          false -> {:ok, []}
          error -> error
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp read_verification_checks(packet_version, verification_check_ids) do
    VerificationCheck
    |> Ash.Query.filter(
      id in ^verification_check_ids and organization_id == ^packet_version.organization_id and
        workspace_id == ^packet_version.workspace_id and lifecycle_state == "required"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
  end

  defp validate_authority_posture(changeset, packet_version, authority_posture) do
    if authority_posture == packet_version.autonomy_posture do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :authority_posture,
        message: "authority_posture must match the packet autonomy posture"
      )
    end
  end

  defp format_lookup_error(%{__exception__: true} = error), do: Exception.message(error)
end
