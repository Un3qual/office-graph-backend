defmodule OfficeGraph.Runs.Changes.ValidateRunRequiredCheckContract do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.Runs.Run
  alias OfficeGraph.WorkPackets.WorkPacketRequiredCheck

  require Ash.Query
  require Logger

  @impl true
  def change(changeset, opts, context) do
    [changeset] = batch_change([changeset], opts, context)
    changeset
  end

  @impl true
  def batch_change(changesets, opts, _context) do
    runs_by_id = read_runs(changesets)

    packet_required_check_reader =
      Keyword.get(opts, :packet_required_check_reader, &read_packet_required_checks/2)

    packet_required_checks = packet_required_check_reader.(changesets, runs_by_id)

    Enum.map(
      changesets,
      &validate_changeset(&1, runs_by_id, packet_required_checks)
    )
  end

  defp validate_changeset(changeset, runs_by_id, packet_required_checks) do
    run_id = attribute(changeset, :run_id)
    verification_check_id = attribute(changeset, :verification_check_id)
    organization_id = attribute(changeset, :organization_id)
    workspace_id = attribute(changeset, :workspace_id)

    with {:ok, run} <-
           fetch_run(
             runs_by_id,
             run_id,
             organization_id,
             workspace_id
           ),
         :ok <-
           validate_packet_required_check(
             run,
             verification_check_id,
             organization_id,
             workspace_id,
             packet_required_checks
           ) do
      changeset
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)
    end
  end

  defp read_runs(changesets) do
    run_ids = changesets |> attributes(:run_id) |> Enum.uniq()

    case run_ids do
      [] ->
        {:ok, %{}}

      run_ids ->
        Run
        |> Ash.Query.filter(id in ^run_ids)
        |> Ash.read(authorize?: false)
        |> case do
          {:ok, runs} -> {:ok, Map.new(runs, &{&1.id, &1})}
          {:error, error} -> {:error, error}
        end
    end
  end

  defp read_packet_required_checks(_changesets, {:error, error}), do: {:error, error}

  defp read_packet_required_checks(changesets, {:ok, runs_by_id}) do
    work_packet_version_ids =
      runs_by_id
      |> Enum.map(fn {_run_id, run} -> run.work_packet_version_id end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    verification_check_ids = changesets |> attributes(:verification_check_id) |> Enum.uniq()

    if work_packet_version_ids == [] or verification_check_ids == [] do
      {:ok, %{}}
    else
      WorkPacketRequiredCheck
      |> Ash.Query.filter(
        work_packet_version_id in ^work_packet_version_ids and
          verification_check_id in ^verification_check_ids
      )
      |> Ash.read(authorize?: false)
      |> case do
        {:ok, required_checks} ->
          {:ok,
           Map.new(required_checks, fn required_check ->
             contract_key =
               {
                 required_check.work_packet_version_id,
                 required_check.verification_check_id,
                 required_check.organization_id,
                 required_check.workspace_id
               }

             {contract_key, true}
           end)}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp attributes(changesets, field) do
    changesets
    |> Enum.map(&attribute(&1, field))
    |> Enum.reject(&is_nil/1)
  end

  defp attribute(changeset, field), do: Ash.Changeset.get_attribute(changeset, field)

  defp fetch_run(_runs_by_id, nil, _organization_id, _workspace_id) do
    {:error, :run_id, "run_id must reference an existing run in the target scope"}
  end

  defp fetch_run(_runs_by_id, _run_id, nil, _workspace_id) do
    {:error, :organization_id, "target organization_id and workspace_id are required"}
  end

  defp fetch_run(_runs_by_id, _run_id, _organization_id, nil) do
    {:error, :workspace_id, "target organization_id and workspace_id are required"}
  end

  defp fetch_run({:error, error}, _run_id, _organization_id, _workspace_id) do
    log_lookup_failure(:run_id, error)
    {:error, :run_id, "run_id could not be validated"}
  end

  defp fetch_run({:ok, runs_by_id}, run_id, organization_id, workspace_id) do
    case Map.get(runs_by_id, run_id) do
      %{organization_id: ^organization_id, workspace_id: ^workspace_id} = run ->
        {:ok, run}

      _missing_or_cross_scope ->
        {:error, :run_id, "run_id must reference an existing run in the target scope"}
    end
  end

  defp validate_packet_required_check(
         %{work_packet_version_id: nil},
         _check_id,
         _org_id,
         _ws_id,
         _packet_required_checks
       ) do
    {:error, :run_id, "run_id must reference a packet-backed run"}
  end

  defp validate_packet_required_check(_run, nil, _org_id, _ws_id, _packet_required_checks) do
    {:error, :verification_check_id,
     "verification_check_id must belong to the run packet version"}
  end

  defp validate_packet_required_check(
         _run,
         _verification_check_id,
         _organization_id,
         _workspace_id,
         {:error, error}
       ) do
    log_lookup_failure(:verification_check_id, error)
    {:error, :verification_check_id, "verification_check_id could not be validated"}
  end

  defp validate_packet_required_check(
         run,
         verification_check_id,
         organization_id,
         workspace_id,
         {:ok, packet_required_checks}
       ) do
    contract_key =
      {run.work_packet_version_id, verification_check_id, organization_id, workspace_id}

    if Map.has_key?(packet_required_checks, contract_key) do
      :ok
    else
      {:error, :verification_check_id,
       "verification_check_id must belong to the run packet version"}
    end
  end

  defp log_lookup_failure(field, error) do
    Logger.warning("run required-check reference lookup failed",
      field: field,
      error: inspect(error)
    )
  end
end
