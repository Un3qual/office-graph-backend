defmodule OfficeGraph.WorkPackets do
  @moduledoc """
  Public boundary for work-packet planning records.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.Operations
  alias OfficeGraph.Repo

  alias OfficeGraph.WorkPackets.{
    Readiness,
    WorkPacket,
    WorkPacketRequiredCheck,
    WorkPacketSourceReference,
    WorkPacketVersion
  }

  alias OfficeGraph.WorkGraph.VerificationCheck

  require Ash.Query

  @work_packet_create_action "work_packet.create"
  @work_packet_version_create_action "work_packet.version.create"

  def graphql_node_type(%WorkPacket{}), do: :work_packet
  def graphql_node_type(_value), do: nil

  def graphql_node(session_context, :work_packet, id) do
    Ash.get(WorkPacket, id, actor: session_context, not_found_error?: false)
  end

  def graphql_node(_session_context, _type, _id), do: {:ok, nil}

  def create_packet(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @work_packet_create_action),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :work_packet_create,
             organization_id: session_context.organization_id
           ) do
      create_packet_records(session_context, operation, attrs)
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
      create_version_records(session_context, operation, packet.id, attrs)
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
    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)
      packet = lock_packet!(session_context, packet_id)

      case existing_version_result(session_context, operation, packet) do
        {:ok, nil} ->
          create_next_version_records!(session_context, operation, packet, attrs)

        {:ok, version_result} ->
          replay_version_result!(version_result, attrs)

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp create_next_version_records!(session_context, operation, packet, attrs) do
    with {:ok, current_version} <- read_current_version(packet),
         :ok <- validate_expected_current_version(packet, current_version, attrs),
         :ok <- validate_source_check_pairs(session_context, attrs) do
      version =
        Repo.ash_create!(
          WorkPacketVersion,
          version_attrs(
            session_context,
            operation,
            packet,
            current_version.version_number + 1,
            attrs
          )
        )

      source_references = create_source_references!(session_context, version, attrs)
      required_checks = create_required_checks!(session_context, version, attrs)

      packet =
        packet
        |> Ash.Changeset.for_update(:set_current_version, %{
          current_version_id: version.id
        })
        |> Repo.ash_update!()

      %{
        packet: packet,
        version: version,
        source_references: source_references,
        required_checks: required_checks
      }
    else
      {:error, error} -> Repo.rollback(error)
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
           %{
             packet: packet,
             version: version,
             source_references: source_references,
             required_checks: required_checks
           }}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp replay_version_result!(
         %{
           version: version,
           source_references: source_references,
           required_checks: required_checks
         } = version_result,
         attrs
       ) do
    if same_version_replay?(version, source_references, required_checks, attrs) do
      version_result
    else
      Repo.rollback({:work_packet_version_operation_conflict, version.id})
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

  defp lock_packet!(session_context, packet_id) do
    WorkPacket
    |> Ash.Query.filter(
      id == ^packet_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> Repo.rollback({:not_found, WorkPacket, packet_id})
      {:ok, packet} -> packet
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp create_packet_records(session_context, operation, attrs) do
    packet_id = Ecto.UUID.generate()
    version_id = Ecto.UUID.generate()

    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)

      case existing_packet_result(session_context, operation) do
        {:ok, nil} ->
          case validate_source_check_pairs(session_context, attrs) do
            :ok ->
              create_packet_records!(
                session_context,
                operation,
                attrs,
                packet_id,
                version_id
              )

            {:error, error} ->
              Repo.rollback(error)
          end

        {:ok, packet_result} ->
          replay_packet_result!(packet_result, attrs)

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp create_packet_records!(
         session_context,
         operation,
         attrs,
         packet_id,
         version_id
       ) do
    packet =
      Repo.ash_create!(
        WorkPacket,
        %{
          id: packet_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          operation_id: operation.id,
          title: attrs[:title]
        }
      )

    version =
      Repo.ash_create!(
        WorkPacketVersion,
        version_attrs(session_context, operation, packet, 1, attrs)
        |> Map.put(:id, version_id)
      )

    source_references = create_source_references!(session_context, version, attrs)
    required_checks = create_required_checks!(session_context, version, attrs)

    packet =
      packet
      |> Ash.Changeset.for_update(:set_current_version, %{
        current_version_id: version.id
      })
      |> Repo.ash_update!()

    %{
      packet: packet,
      version: version,
      source_references: source_references,
      required_checks: required_checks
    }
  end

  defp version_attrs(session_context, operation, packet, version_number, attrs) do
    %{
      id: Ecto.UUID.generate(),
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

  defp create_source_references!(session_context, version, attrs) do
    inputs =
      attrs
      |> Map.get(:source_graph_item_ids, [])
      |> Enum.with_index()
      |> Enum.map(fn {graph_item_id, position} ->
        %{
          id: Ecto.UUID.generate(),
          work_packet_version_id: version.id,
          graph_item_id: graph_item_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          position: position
        }
      end)

    Repo.ash_bulk_create!(WorkPacketSourceReference, inputs)
  end

  defp create_required_checks!(session_context, version, attrs) do
    inputs =
      attrs
      |> Map.get(:verification_check_ids, [])
      |> Enum.with_index()
      |> Enum.map(fn {verification_check_id, position} ->
        %{
          id: Ecto.UUID.generate(),
          work_packet_version_id: version.id,
          verification_check_id: verification_check_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          position: position
        }
      end)

    Repo.ash_bulk_create!(WorkPacketRequiredCheck, inputs)
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
        with {:ok, version} <- read_current_version(packet),
             {:ok, source_references} <- read_source_references(version.id),
             {:ok, required_checks} <- read_required_checks(version.id) do
          {:ok,
           %{
             packet: packet,
             version: version,
             source_references: source_references,
             required_checks: required_checks
           }}
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

  defp replay_packet_result!(
         %{
           packet: packet,
           version: version,
           source_references: source_references,
           required_checks: required_checks
         } =
           packet_result,
         attrs
       ) do
    if same_packet_replay?(packet, version, source_references, required_checks, attrs) do
      packet_result
    else
      Repo.rollback({:work_packet_operation_conflict, packet.id})
    end
  end

  defp same_packet_replay?(packet, version, source_references, required_checks, attrs) do
    packet.title == attrs[:title] and
      packet.state == version.lifecycle_state and
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

  defp lock_operation!(operation_id) do
    case Operations.lock_operation(operation_id) do
      {:ok, operation} -> operation
      {:error, error} -> Repo.rollback(error)
    end
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

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, error}), do: {:error, error}
  defp normalize_transaction_result(other), do: other
end
