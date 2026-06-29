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
  alias OfficeGraph.Operations.OperationCorrelation
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

  def create_packet(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @work_packet_create_action),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :work_packet_create,
             organization_id: session_context.organization_id
           ),
         :ok <- validate_source_check_pairs(session_context, attrs) do
      create_packet_records(session_context, operation, attrs)
    end
  end

  def ready_for_execution_attrs?(attrs) when is_map(attrs) do
    Readiness.ready?(attrs)
  end

  def mismatched_source_check_ids(source_graph_item_ids, verification_checks) do
    Readiness.mismatched_source_check_ids(source_graph_item_ids, verification_checks)
  end

  defp validate_source_check_pairs(session_context, attrs) do
    source_graph_item_ids = Map.get(attrs, :source_graph_item_ids, [])
    verification_check_ids = Map.get(attrs, :verification_check_ids, [])

    with true <- source_graph_item_ids != [] and verification_check_ids != [],
         {:ok, verification_checks} <-
           read_scoped_verification_checks(session_context, verification_check_ids),
         true <- length(verification_checks) == length(Enum.uniq(verification_check_ids)),
         [] <- Readiness.mismatched_source_check_ids(source_graph_item_ids, verification_checks) do
      :ok
    else
      false -> :ok
      [_id | _ids] -> {:error, source_check_mismatch_error()}
      {:error, error} -> {:error, error}
      _missing_or_forbidden_reference -> :ok
    end
  end

  defp read_scoped_verification_checks(session_context, verification_check_ids) do
    VerificationCheck
    |> Ash.Query.filter(
      id in ^verification_check_ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read(authorize?: false)
  end

  defp source_check_mismatch_error do
    Ash.Error.to_error_class(
      Ash.Error.Changes.InvalidChanges.exception(
        fields: [:source_graph_item_ids, :verification_check_ids],
        message: "source_graph_item_ids must include every verification check graph item"
      )
    )
  end

  defp create_packet_records(session_context, operation, attrs) do
    packet_id = Ecto.UUID.generate()
    version_id = Ecto.UUID.generate()

    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)

      case existing_packet_result(session_context, operation) do
        {:ok, nil} ->
          create_packet_records!(
            session_context,
            operation,
            attrs,
            packet_id,
            version_id
          )

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
      ash_create!(
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
      ash_create!(
        WorkPacketVersion,
        %{
          id: version_id,
          work_packet_id: packet.id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          operation_id: operation.id,
          version_number: 1,
          objective: attrs[:objective],
          context_summary: attrs[:context_summary],
          requirements: attrs[:requirements],
          success_criteria: attrs[:success_criteria],
          autonomy_posture: attrs[:autonomy_posture],
          source_graph_item_ids: Map.get(attrs, :source_graph_item_ids, []),
          verification_check_ids: Map.get(attrs, :verification_check_ids, [])
        }
      )

    source_references =
      attrs
      |> Map.get(:source_graph_item_ids, [])
      |> Enum.map(fn graph_item_id ->
        ash_create!(
          WorkPacketSourceReference,
          %{
            id: Ecto.UUID.generate(),
            work_packet_version_id: version.id,
            graph_item_id: graph_item_id,
            organization_id: session_context.organization_id,
            workspace_id: session_context.workspace_id
          }
        )
      end)

    required_checks =
      attrs
      |> Map.get(:verification_check_ids, [])
      |> Enum.map(fn verification_check_id ->
        ash_create!(
          WorkPacketRequiredCheck,
          %{
            id: Ecto.UUID.generate(),
            work_packet_version_id: version.id,
            verification_check_id: verification_check_id,
            organization_id: session_context.organization_id,
            workspace_id: session_context.workspace_id
          }
        )
      end)

    packet =
      packet
      |> Ash.Changeset.for_update(:set_current_version, %{
        current_version_id: version.id
      })
      |> ash_update!()

    %{
      packet: packet,
      version: version,
      source_references: source_references,
      required_checks: required_checks
    }
  end

  defp validate_operation_context(session_context, operation)
       when is_map(session_context) and is_map(operation) do
    if operation.principal_id == session_context.principal_id and
         operation.session_id == session_context.session_id and
         operation.organization_id == session_context.organization_id and
         operation.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_operation_context(_session_context, _operation), do: {:error, :forbidden}

  defp validate_operation_action(operation, expected_action) do
    case operation.action do
      ^expected_action -> :ok
      _other -> {:error, {:invalid_operation_action, operation.id, expected_action}}
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
      version.objective == attrs[:objective] and
      version.context_summary == attrs[:context_summary] and
      version.requirements == attrs[:requirements] and
      version.success_criteria == attrs[:success_criteria] and
      version.autonomy_posture == attrs[:autonomy_posture] and
      source_graph_item_ids(source_references) ==
        MapSet.new(Map.get(attrs, :source_graph_item_ids, [])) and
      required_check_ids(required_checks) ==
        MapSet.new(Map.get(attrs, :verification_check_ids, []))
  end

  defp source_graph_item_ids(source_references) do
    source_references
    |> Enum.map(& &1.graph_item_id)
    |> MapSet.new()
  end

  defp required_check_ids(required_checks) do
    required_checks
    |> Enum.map(& &1.verification_check_id)
    |> MapSet.new()
  end

  defp lock_operation!(operation_id) do
    OperationCorrelation
    |> Ash.Query.filter(id == ^operation_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> Repo.rollback({:not_found, OperationCorrelation, operation_id})
      {:ok, operation} -> operation
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp read_source_references(version_id) do
    WorkPacketSourceReference
    |> Ash.Query.filter(work_packet_version_id == ^version_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_required_checks(version_id) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(work_packet_version_id == ^version_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp ash_create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, record, notifications} -> unwrap_notification_result({record, notifications})
      {:ok, record} -> record
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp ash_update!(changeset) do
    changeset
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, record, notifications} -> unwrap_notification_result({record, notifications})
      {:ok, record} -> record
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp unwrap_notification_result({record, _notifications}), do: record

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, error}), do: {:error, error}
  defp normalize_transaction_result(other), do: other
end
