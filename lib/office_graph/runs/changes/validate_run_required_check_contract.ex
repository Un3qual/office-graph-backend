defmodule OfficeGraph.Runs.Changes.ValidateRunRequiredCheckContract do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.Runs.Run
  alias OfficeGraph.WorkPackets.WorkPacketRequiredCheck

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    run_id = Ash.Changeset.get_attribute(changeset, :run_id)
    verification_check_id = Ash.Changeset.get_attribute(changeset, :verification_check_id)
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)

    with {:ok, run} <- fetch_scoped_run(run_id, organization_id, workspace_id),
         :ok <-
           validate_packet_required_check(
             run,
             verification_check_id,
             organization_id,
             workspace_id
           ) do
      changeset
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)
    end
  end

  defp fetch_scoped_run(nil, _organization_id, _workspace_id) do
    {:error, :run_id, "run_id must reference an existing run in the target scope"}
  end

  defp fetch_scoped_run(_run_id, nil, _workspace_id) do
    {:error, :organization_id, "target organization_id and workspace_id are required"}
  end

  defp fetch_scoped_run(_run_id, _organization_id, nil) do
    {:error, :workspace_id, "target organization_id and workspace_id are required"}
  end

  defp fetch_scoped_run(run_id, organization_id, workspace_id) do
    Run
    |> Ash.Query.filter(id == ^run_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id} = run} ->
        {:ok, run}

      {:ok, _missing_or_cross_scope} ->
        {:error, :run_id, "run_id must reference an existing run in the target scope"}

      {:error, error} ->
        {:error, :run_id, "run_id lookup failed: #{format_lookup_error(error)}"}
    end
  end

  defp validate_packet_required_check(%{work_packet_version_id: nil}, _check_id, _org_id, _ws_id) do
    {:error, :run_id, "run_id must reference a packet-backed run"}
  end

  defp validate_packet_required_check(_run, nil, _org_id, _ws_id) do
    {:error, :verification_check_id,
     "verification_check_id must belong to the run packet version"}
  end

  defp validate_packet_required_check(run, verification_check_id, organization_id, workspace_id) do
    if packet_required_check?(
         run.work_packet_version_id,
         verification_check_id,
         organization_id,
         workspace_id
       ) do
      :ok
    else
      {:error, :verification_check_id,
       "verification_check_id must belong to the run packet version"}
    end
  end

  defp packet_required_check?(
         work_packet_version_id,
         verification_check_id,
         organization_id,
         workspace_id
       ) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(
      work_packet_version_id == ^work_packet_version_id and
        verification_check_id == ^verification_check_id and
        organization_id == ^organization_id and workspace_id == ^workspace_id
    )
    |> Ash.exists?(authorize?: false)
  end

  defp format_lookup_error(%{__exception__: true} = error), do: Exception.message(error)
  defp format_lookup_error(error), do: inspect(error)
end
