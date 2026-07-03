defmodule OfficeGraph.Runs.Changes.ValidateObservationRunReferences do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.Runs.{Run, RunRequiredCheck}
  alias OfficeGraph.Runs.Changes.ScopedRead
  alias OfficeGraph.WorkGraph.VerificationCheck
  alias OfficeGraph.WorkPackets.WorkPacketSourceReference

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    run_id = Ash.Changeset.get_attribute(changeset, :work_run_id)
    verification_check_id = Ash.Changeset.get_attribute(changeset, :verification_check_id)
    graph_item_id = Ash.Changeset.get_attribute(changeset, :graph_item_id)
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)

    with {:ok, run} <-
           ScopedRead.fetch(
             Run,
             run_id,
             organization_id,
             workspace_id,
             :work_run_id,
             "work_run_id must reference an existing run in the target scope"
           ) do
      changeset
      |> validate_verification_check(run, verification_check_id)
      |> validate_graph_item(run, verification_check_id, graph_item_id)
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)
    end
  end

  defp validate_verification_check(changeset, _run, nil), do: changeset

  defp validate_verification_check(changeset, run, verification_check_id) do
    if run_requires_check?(run, verification_check_id) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :verification_check_id,
        message: "verification_check_id must reference a required check for the run"
      )
    end
  end

  defp validate_graph_item(changeset, _run, nil, nil), do: changeset
  defp validate_graph_item(changeset, _run, _verification_check_id, nil), do: changeset

  defp validate_graph_item(changeset, run, nil, graph_item_id) do
    if graph_item_belongs_to_run?(run, graph_item_id) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :graph_item_id,
        message: "graph_item_id must reference a graph item selected by the run"
      )
    end
  end

  defp validate_graph_item(changeset, _run, verification_check_id, graph_item_id) do
    case fetch_verification_check(verification_check_id) do
      {:ok, %{graph_item_id: ^graph_item_id}} ->
        changeset

      {:ok, _missing_or_mismatch} ->
        Ash.Changeset.add_error(changeset,
          field: :graph_item_id,
          message: "graph_item_id must match the verification check graph item"
        )

      {:error, error} ->
        Ash.Changeset.add_error(changeset,
          field: :verification_check_id,
          message: "verification_check_id lookup failed: #{format_lookup_error(error)}"
        )
    end
  end

  defp run_requires_check?(run, verification_check_id) do
    RunRequiredCheck
    |> Ash.Query.filter(
      run_id == ^run.id and verification_check_id == ^verification_check_id and
        organization_id == ^run.organization_id and workspace_id == ^run.workspace_id
    )
    |> Ash.exists?(authorize?: false)
  end

  defp graph_item_belongs_to_run?(run, graph_item_id) do
    packet_source_graph_item?(run, graph_item_id) or
      required_check_graph_item?(run, graph_item_id)
  end

  defp packet_source_graph_item?(%{work_packet_version_id: nil}, _graph_item_id), do: false

  defp packet_source_graph_item?(run, graph_item_id) do
    WorkPacketSourceReference
    |> Ash.Query.filter(
      work_packet_version_id == ^run.work_packet_version_id and graph_item_id == ^graph_item_id and
        organization_id == ^run.organization_id and workspace_id == ^run.workspace_id
    )
    |> Ash.exists?(authorize?: false)
  end

  defp required_check_graph_item?(run, graph_item_id) do
    required_check_ids =
      RunRequiredCheck
      |> Ash.Query.filter(
        run_id == ^run.id and organization_id == ^run.organization_id and
          workspace_id == ^run.workspace_id
      )
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.verification_check_id)

    VerificationCheck
    |> Ash.Query.filter(
      id in ^required_check_ids and graph_item_id == ^graph_item_id and
        organization_id == ^run.organization_id and workspace_id == ^run.workspace_id
    )
    |> Ash.exists?(authorize?: false)
  end

  defp fetch_verification_check(verification_check_id) do
    VerificationCheck
    |> Ash.Query.filter(id == ^verification_check_id)
    |> Ash.read_one(authorize?: false)
  end

  defp format_lookup_error(%{__exception__: true} = error), do: Exception.message(error)
end
