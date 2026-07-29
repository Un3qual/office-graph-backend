defmodule OfficeGraph.WorkPackets do
  @moduledoc """
  Public boundary for work-packet planning records.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.CommandSupport,
      OfficeGraph.Operations,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.Operations

  alias OfficeGraph.WorkPackets.{
    PacketActionResult,
    Readiness,
    PacketResult,
    WorkPacket,
    WorkPacketRequiredCheck,
    WorkPacketSourceReference,
    WorkPacketVersion
  }

  alias OfficeGraph.WorkGraph.VerificationCheck

  require Ash.Query

  @work_packet_create_action "work_packet.create"
  @work_packet_version_create_action "work_packet.version.create"

  defguardp is_packet_business_error(error)
            when is_tuple(error) and
                   elem(error, 0) in [
                     :packet_current_version_mismatch,
                     :stale_packet_version,
                     :work_packet_operation_conflict,
                     :work_packet_version_operation_conflict
                   ]

  @behaviour Ash.Resource.Actions.Implementation

  @impl true
  def run(input, [mode: :create_packet], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id) do
      case create_packet_records(
             session_context,
             operation,
             Map.delete(attrs, :operation_id)
           ) do
        {:ok, result} -> PacketActionResult.accepted(result)
        {:error, error} when is_packet_business_error(error) -> PacketActionResult.rejected(error)
        {:error, error} -> {:error, error}
      end
    end
  end

  def run(input, [mode: :create_version], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id) do
      case create_version_records(
             session_context,
             operation,
             attrs.packet_id,
             Map.drop(attrs, [:operation_id, :packet_id])
           ) do
        {:ok, result} -> PacketActionResult.accepted(result)
        {:error, error} when is_packet_business_error(error) -> PacketActionResult.rejected(error)
        {:error, error} -> {:error, error}
      end
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def get_packet_for_version_command(session_context, id) do
    Operations.read_command_target(
      WorkPacket,
      :read_for_version_command,
      session_context,
      id
    )
  end

  def create_packet(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @work_packet_create_action),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :work_packet_create,
             organization_id: session_context.organization_id
           ) do
      WorkPacket
      |> Ash.ActionInput.for_action(
        :persist_packet_contract,
        Map.put(attrs, :operation_id, operation.id)
      )
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> case do
        {:ok, %PacketActionResult{} = result} -> PacketActionResult.to_public_result(result)
        {:error, error} -> {:error, error}
      end
    end
  end

  def create_version(session_context, operation, packet, attrs)
      when is_map(packet) and is_map(attrs) do
    command_input = Map.put(attrs, :packet_id, packet.id)

    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <-
           Operations.validate_operation_action(operation, @work_packet_version_create_action),
         :ok <- Operations.validate_command_replay(operation, command_input),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :work_packet_version_create,
             organization_id: session_context.organization_id
           ) do
      WorkPacket
      |> Ash.ActionInput.for_action(
        :persist_packet_version_contract,
        attrs
        |> Map.put(:operation_id, operation.id)
        |> Map.put(:packet_id, packet.id)
      )
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> case do
        {:ok, %PacketActionResult{} = result} -> PacketActionResult.to_public_result(result)
        {:error, error} -> {:error, error}
      end
    end
  end

  def ready_for_execution_attrs?(attrs) when is_map(attrs) do
    Readiness.ready?(attrs)
  end

  def readiness_blocker_reasons(attrs) when is_map(attrs) do
    Readiness.blocker_reasons(attrs)
  end

  def missing_string_blocker(attrs, key, reason) when is_map(attrs) do
    Readiness.missing_string_blocker(attrs, key, reason)
  end

  def mismatched_source_check_ids(source_graph_item_ids, verification_checks) do
    Readiness.mismatched_source_check_ids(source_graph_item_ids, verification_checks)
  end

  defp validate_source_check_pairs(session_context, attrs) do
    source_graph_item_ids = Map.get(attrs, :source_graph_item_ids, [])
    verification_check_ids = Map.get(attrs, :verification_check_ids, [])

    with :ok <- validate_unique_source_graph_item_ids(source_graph_item_ids),
         :ok <- validate_unique_verification_check_ids(verification_check_ids),
         {:ok, verification_checks} <-
           read_required_verification_checks(session_context, verification_check_ids),
         :ok <- validate_required_verification_checks(verification_check_ids, verification_checks),
         :ok <- validate_source_check_pairing(source_graph_item_ids, verification_checks) do
      :ok
    end
  end

  defp validate_unique_source_graph_item_ids([]), do: :ok

  defp validate_unique_source_graph_item_ids(source_graph_item_ids) do
    if length(source_graph_item_ids) == length(Enum.uniq(source_graph_item_ids)) do
      :ok
    else
      {:error, duplicate_source_graph_item_ids_error()}
    end
  end

  defp validate_unique_verification_check_ids([]), do: :ok

  defp validate_unique_verification_check_ids(verification_check_ids) do
    if length(verification_check_ids) == length(Enum.uniq(verification_check_ids)) do
      :ok
    else
      {:error, duplicate_verification_check_ids_error()}
    end
  end

  defp validate_required_verification_checks([], []), do: :ok

  defp validate_required_verification_checks(verification_check_ids, verification_checks) do
    if length(verification_checks) == length(verification_check_ids) do
      :ok
    else
      {:error, required_verification_checks_error()}
    end
  end

  defp validate_source_check_pairing([], _verification_checks), do: :ok
  defp validate_source_check_pairing(_source_graph_item_ids, []), do: :ok

  defp validate_source_check_pairing(source_graph_item_ids, verification_checks) do
    case Readiness.mismatched_source_check_ids(source_graph_item_ids, verification_checks) do
      [] -> :ok
      [_id | _ids] -> {:error, source_check_mismatch_error()}
    end
  end

  defp read_required_verification_checks(_session_context, []), do: {:ok, []}

  defp read_required_verification_checks(session_context, verification_check_ids) do
    VerificationCheck
    |> Ash.Query.filter(
      id in ^verification_check_ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and lifecycle_state == "required"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, verification_checks} -> {:ok, verification_checks}
      {:error, error} -> {:error, error}
    end
  end

  defp duplicate_source_graph_item_ids_error do
    Ash.Error.to_error_class(
      Ash.Error.Changes.InvalidChanges.exception(
        fields: [:source_graph_item_ids],
        message: "source_graph_item_ids must not include duplicate ids"
      )
    )
  end

  defp duplicate_verification_check_ids_error do
    Ash.Error.to_error_class(
      Ash.Error.Changes.InvalidChanges.exception(
        fields: [:verification_check_ids],
        message: "verification_check_ids must not include duplicate ids"
      )
    )
  end

  defp required_verification_checks_error do
    Ash.Error.to_error_class(
      Ash.Error.Changes.InvalidChanges.exception(
        fields: [:verification_check_ids],
        message: "verification_check_ids must reference required verification checks"
      )
    )
  end

  defp source_check_mismatch_error do
    Ash.Error.to_error_class(
      Ash.Error.Changes.InvalidChanges.exception(
        fields: [:source_graph_item_ids, :verification_check_ids],
        message: "source_graph_item_ids must include every verification check graph item"
      )
    )
  end

  defp create_version_records(session_context, operation, packet_id, attrs) do
    with {:ok, packet} <-
           Operations.lock_scoped_target(WorkPacket, session_context, packet_id),
         {:ok, existing_result} <-
           existing_version_result(session_context, operation, packet) do
      case existing_result do
        nil -> create_next_version_records(session_context, operation, packet, attrs)
        version_result -> replay_version_result(version_result, attrs)
      end
    end
  end

  defp create_next_version_records(session_context, operation, packet, attrs) do
    with {:ok, current_version} <- read_current_version(packet),
         :ok <- validate_expected_current_version(packet, current_version, attrs),
         :ok <- validate_source_check_pairs(session_context, attrs),
         {:ok, version, _version_notifications} <-
           WorkPacketVersion
           |> Ash.Changeset.for_create(
             :create,
             version_attrs(
               session_context,
               operation,
               packet,
               current_version.version_number + 1,
               attrs
             )
           )
           |> Ash.create(authorize?: false, return_notifications?: true),
         {:ok, source_references} <-
           create_source_references(session_context, version, attrs),
         {:ok, required_checks} <-
           create_required_checks(session_context, version, attrs),
         {:ok, packet, _packet_notifications} <-
           packet
           |> Ash.Changeset.for_update(:set_current_version, %{
             current_version_id: version.id
           })
           |> Ash.update(authorize?: false, return_notifications?: true) do
      {:ok,
       PacketResult.build!(
         packet,
         version,
         source_references,
         required_checks
       )}
    end
  end

  defp validate_expected_current_version(packet, current_version, attrs) do
    if attrs[:expected_current_version_id] == current_version.id do
      :ok
    else
      {:error, {:stale_packet_version, packet.id, current_version.id}}
    end
  end

  defp existing_version_result(session_context, operation, packet) do
    WorkPacketVersion
    |> Ash.Query.filter(
      work_packet_id == ^packet.id and operation_id == ^operation.id and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, version} ->
        with {:ok, source_references} <- read_source_references(version.id),
             {:ok, required_checks} <- read_required_checks(version.id) do
          {:ok,
           PacketResult.build!(
             packet,
             version,
             source_references,
             required_checks
           )}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp replay_version_result(
         %PacketResult{
           version: version,
           source_references: source_references,
           required_checks: required_checks
         } = version_result,
         attrs
       ) do
    if same_version_replay?(version, source_references, required_checks, attrs) do
      {:ok, version_result}
    else
      {:error, {:work_packet_version_operation_conflict, version.id}}
    end
  end

  defp same_version_replay?(version, source_references, required_checks, attrs) do
    version.title == attrs[:title] and
      version.objective == attrs[:objective] and
      version.context_summary == attrs[:context_summary] and
      version.requirements == attrs[:requirements] and
      version.success_criteria == attrs[:success_criteria] and
      version.autonomy_posture == attrs[:autonomy_posture] and
      source_graph_item_ids(source_references) == Map.get(attrs, :source_graph_item_ids, []) and
      required_check_ids(required_checks) == Map.get(attrs, :verification_check_ids, [])
  end

  defp create_packet_records(session_context, operation, attrs) do
    with {:ok, existing_result} <- existing_packet_result(session_context, operation) do
      case existing_result do
        nil ->
          with :ok <- validate_source_check_pairs(session_context, attrs) do
            create_packet_contract(session_context, operation, attrs)
          end

        packet_result ->
          replay_packet_result(packet_result, attrs)
      end
    end
  end

  defp create_packet_contract(session_context, operation, attrs) do
    with {:ok, packet, _packet_notifications} <-
           WorkPacket
           |> Ash.Changeset.for_create(:create, %{
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id,
             operation_id: operation.id,
             title: attrs[:title]
           })
           |> Ash.create(authorize?: false, return_notifications?: true),
         {:ok, version, _version_notifications} <-
           WorkPacketVersion
           |> Ash.Changeset.for_create(
             :create,
             version_attrs(session_context, operation, packet, 1, attrs)
           )
           |> Ash.create(authorize?: false, return_notifications?: true),
         {:ok, source_references} <-
           create_source_references(session_context, version, attrs),
         {:ok, required_checks} <-
           create_required_checks(session_context, version, attrs),
         {:ok, packet, _update_notifications} <-
           packet
           |> Ash.Changeset.for_update(:set_current_version, %{
             current_version_id: version.id
           })
           |> Ash.update(authorize?: false, return_notifications?: true) do
      {:ok,
       PacketResult.build!(
         packet,
         version,
         source_references,
         required_checks
       )}
    end
  end

  defp version_attrs(session_context, operation, packet, version_number, attrs) do
    %{
      work_packet_id: packet.id,
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id,
      operation_id: operation.id,
      version_number: version_number,
      title: attrs[:title],
      objective: attrs[:objective],
      context_summary: attrs[:context_summary],
      requirements: attrs[:requirements],
      success_criteria: attrs[:success_criteria],
      autonomy_posture: attrs[:autonomy_posture],
      source_graph_item_ids: Map.get(attrs, :source_graph_item_ids, []),
      verification_check_ids: Map.get(attrs, :verification_check_ids, [])
    }
  end

  defp create_source_references(session_context, version, attrs) do
    inputs =
      attrs
      |> Map.get(:source_graph_item_ids, [])
      |> Enum.with_index()
      |> Enum.map(fn {graph_item_id, position} ->
        %{
          work_packet_version_id: version.id,
          graph_item_id: graph_item_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          position: position
        }
      end)

    create_packet_children(WorkPacketSourceReference, inputs)
  end

  defp create_required_checks(session_context, version, attrs) do
    inputs =
      attrs
      |> Map.get(:verification_check_ids, [])
      |> Enum.with_index()
      |> Enum.map(fn {verification_check_id, position} ->
        %{
          work_packet_version_id: version.id,
          verification_check_id: verification_check_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          position: position
        }
      end)

    create_packet_children(WorkPacketRequiredCheck, inputs)
  end

  defp create_packet_children(_resource, []), do: {:ok, []}

  defp create_packet_children(resource, inputs) do
    case Ash.bulk_create(inputs, resource, :create,
           authorize?: false,
           return_errors?: true,
           return_notifications?: true,
           return_records?: true,
           sorted?: true,
           stop_on_error?: true,
           transaction: false
         ) do
      %Ash.BulkResult{status: :success, records: records} ->
        {:ok, records}

      %Ash.BulkResult{errors: errors} when is_list(errors) and errors != [] ->
        {:error, Ash.Error.to_error_class(errors)}

      %Ash.BulkResult{status: status} ->
        {:error, {:packet_child_create_failed, resource, status}}
    end
  end

  defp existing_packet_result(session_context, operation) do
    WorkPacket
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        operation_id == ^operation.id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, packet} ->
        with {:ok, _current_version} <- read_current_version(packet),
             {:ok, version} <- read_version_for_operation(packet, operation),
             {:ok, source_references} <- read_source_references(version.id),
             {:ok, required_checks} <- read_required_checks(version.id) do
          {:ok,
           PacketResult.build!(
             packet,
             version,
             source_references,
             required_checks
           )}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp read_current_version(%{current_version_id: nil} = packet) do
    {:error, {:not_found, WorkPacketVersion, packet.current_version_id}}
  end

  defp read_current_version(packet) do
    WorkPacketVersion
    |> Ash.Query.filter(
      id == ^packet.current_version_id and work_packet_id == ^packet.id and
        organization_id == ^packet.organization_id and workspace_id == ^packet.workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:error, {:packet_current_version_mismatch, packet.id, packet.current_version_id}}

      {:ok, version} ->
        {:ok, version}

      {:error, error} ->
        {:error, error}
    end
  end

  defp read_version_for_operation(packet, operation) do
    WorkPacketVersion
    |> Ash.Query.filter(
      work_packet_id == ^packet.id and operation_id == ^operation.id and
        organization_id == ^packet.organization_id and workspace_id == ^packet.workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, WorkPacketVersion, operation.id}}
      {:ok, version} -> {:ok, version}
      {:error, error} -> {:error, error}
    end
  end

  defp replay_packet_result(
         %PacketResult{
           packet: packet,
           version: version,
           source_references: source_references,
           required_checks: required_checks
         } =
           packet_result,
         attrs
       ) do
    if same_packet_replay?(packet, version, source_references, required_checks, attrs) do
      {:ok, packet_result}
    else
      {:error, {:work_packet_operation_conflict, packet.id}}
    end
  end

  defp same_packet_replay?(packet, version, source_references, required_checks, attrs) do
    version.work_packet_id == packet.id and
      version.operation_id == packet.operation_id and
      version.version_number == 1 and
      version.title == attrs[:title] and
      version.objective == attrs[:objective] and
      version.context_summary == attrs[:context_summary] and
      version.requirements == attrs[:requirements] and
      version.success_criteria == attrs[:success_criteria] and
      version.autonomy_posture == attrs[:autonomy_posture] and
      source_graph_item_ids(source_references) ==
        Map.get(attrs, :source_graph_item_ids, []) and
      required_check_ids(required_checks) ==
        Map.get(attrs, :verification_check_ids, [])
  end

  defp source_graph_item_ids(source_references) do
    Enum.map(source_references, & &1.graph_item_id)
  end

  defp required_check_ids(required_checks) do
    Enum.map(required_checks, & &1.verification_check_id)
  end

  defp read_source_references(version_id) do
    WorkPacketSourceReference
    |> Ash.Query.filter(work_packet_version_id == ^version_id)
    |> Ash.Query.sort(position: :asc, inserted_at: :asc, id: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_required_checks(version_id) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(work_packet_version_id == ^version_id)
    |> Ash.Query.sort(position: :asc, inserted_at: :asc, id: :asc)
    |> Ash.read(authorize?: false)
  end
end
