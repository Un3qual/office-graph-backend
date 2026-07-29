defmodule OfficeGraph.Integrations.ManualIntakeActionResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false
    field :duplicate, :boolean, allow_nil?: false
    field :conflict_id, :uuid

    field :raw_archive, :struct, constraints: [instance_of: OfficeGraph.Integrations.RawArchive]

    field :normalized_event, :struct,
      constraints: [instance_of: OfficeGraph.Integrations.NormalizedIntakeEvent]

    field :proposed_changes, {:array, :struct},
      allow_nil?: false,
      constraints: [items: [instance_of: OfficeGraph.ProposedChanges.ProposedGraphChange]]
  end

  def persisted(raw_archive, normalized_event, duplicate, proposed_changes) do
    new(
      status: "persisted",
      raw_archive: raw_archive,
      normalized_event: normalized_event,
      duplicate: duplicate,
      proposed_changes: proposed_changes
    )
  end

  def conflict(accepted_id) do
    new(
      status: "conflict",
      conflict_id: accepted_id,
      duplicate: false,
      proposed_changes: []
    )
  end

  def to_public_result(%__MODULE__{
        status: "persisted",
        raw_archive: raw_archive,
        normalized_event: normalized_event,
        duplicate: duplicate,
        proposed_changes: proposed_changes
      }) do
    {:ok,
     %{
       raw_archive: raw_archive,
       normalized_event: normalized_event,
       duplicate?: duplicate,
       proposed_changes: proposed_changes
     }}
  end

  def to_public_result(%__MODULE__{status: "conflict", conflict_id: accepted_id}) do
    {:error, {:manual_intake_replay_conflict, accepted_id}}
  end
end

defmodule OfficeGraph.Integrations.Actions.PersistManualIntake do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.DurableDelivery

  alias OfficeGraph.Integrations.{
    ExternalSource,
    ManualIntakeActionResult,
    ManualIntakePersistence,
    NormalizedIntakeEvent,
    RawArchive
  }

  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges

  require Ash.Query

  @manual_intake_action "manual_intake.submit"

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    attrs = input.arguments

    with {:ok, operation} <- operation_for_intake(attrs.operation_id),
         :ok <- validate_operation(session_context, operation),
         {:ok, existing} <- existing_command_intake(session_context, operation) do
      case existing do
        nil -> record_intake(session_context, operation, attrs)
        result -> {:ok, result}
      end
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  defp operation_for_intake(operation_id) do
    with {:ok, operation} <- Operations.read_operation(operation_id) do
      if is_binary(operation.command_input_digest) do
        Operations.lock_operation(operation_id)
      else
        {:ok, operation}
      end
    end
  end

  defp validate_operation(session_context, operation) do
    matching? =
      operation.principal_id == session_context.principal_id and
        operation.session_id == session_context.session_id and
        operation.organization_id == session_context.organization_id and
        operation.workspace_id == session_context.workspace_id and
        operation.action == @manual_intake_action

    if matching?, do: :ok, else: {:error, :forbidden}
  end

  defp existing_command_intake(session_context, operation) do
    if is_binary(operation.command_input_digest) do
      NormalizedIntakeEvent
      |> Ash.Query.filter(
        organization_id == ^session_context.organization_id and
          workspace_id == ^session_context.workspace_id and operation_id == ^operation.id
      )
      |> Ash.read_one(authorize?: false)
      |> case do
        {:ok, nil} -> {:ok, nil}
        {:ok, normalized_event} -> load_intake(session_context, normalized_event)
        {:error, error} -> {:error, error}
      end
    else
      {:ok, nil}
    end
  end

  defp load_intake(session_context, normalized_event) do
    with {:ok, raw_archive} <-
           Ash.get(RawArchive, normalized_event.raw_archive_id, authorize?: false) do
      proposed_changes =
        ProposedChanges.for_normalized_event(session_context, normalized_event.id)

      ManualIntakeActionResult.persisted(
        raw_archive,
        normalized_event,
        normalized_event.outcome == "duplicate",
        proposed_changes
      )
    end
  end

  defp record_intake(session_context, operation, attrs) do
    with {:ok, source} <- ensure_source(attrs.source_identity),
         {:ok, duplicate_of} <- accepted_duplicate(session_context, attrs) do
      case duplicate_of do
        nil ->
          persist_intake(session_context, operation, attrs, source, nil)

        duplicate_of ->
          case duplicate_content_matches?(duplicate_of, attrs.body) do
            {:ok, true} ->
              persist_intake(session_context, operation, attrs, source, duplicate_of)

            {:ok, false} ->
              ManualIntakeActionResult.conflict(duplicate_of.id)

            {:error, error} ->
              {:error, error}
          end
      end
    end
  end

  defp ensure_source(source_identity) do
    ExternalSource
    |> Ash.Changeset.for_create(:ensure, %{
      key: source_identity,
      name: "Manual Intake",
      kind: "manual"
    })
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp accepted_duplicate(session_context, attrs) do
    NormalizedIntakeEvent
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        source_identity == ^attrs.source_identity and
        replay_identity == ^attrs.replay_identity and outcome == "accepted"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp duplicate_content_matches?(duplicate, body) do
    case Ash.get(RawArchive, duplicate.raw_archive_id, authorize?: false) do
      {:ok, %{content_hash: hash}} -> {:ok, hash == content_hash(body)}
      {:error, error} -> {:error, error}
    end
  end

  defp persist_intake(session_context, operation, attrs, source, duplicate_of) do
    outcome = if duplicate_of, do: "duplicate", else: "accepted"

    with :ok <- ManualIntakePersistence.before_write(:raw_archive, attrs),
         {:ok, raw_archive} <-
           create(RawArchive, %{
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id,
             source_id: source.id,
             operation_id: operation.id,
             content_hash: content_hash(attrs.body),
             body: attrs.body
           }),
         {:ok, normalized_event} <-
           create(NormalizedIntakeEvent, %{
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id,
             raw_archive_id: raw_archive.id,
             operation_id: operation.id,
             source_identity: attrs.source_identity,
             replay_identity: attrs.replay_identity,
             outcome: outcome,
             duplicate_of_id: duplicate_of && duplicate_of.id
           }),
         {:ok, proposed_changes} <-
           proposed_changes(
             session_context,
             operation,
             attrs,
             normalized_event,
             outcome
           ),
         :ok <-
           record_durable_acceptance(
             session_context,
             operation,
             normalized_event,
             outcome
           ) do
      ManualIntakeActionResult.persisted(
        raw_archive,
        normalized_event,
        outcome == "duplicate",
        proposed_changes
      )
    end
  end

  defp proposed_changes(_session_context, _operation, _attrs, _normalized_event, "duplicate"),
    do: {:ok, []}

  defp proposed_changes(session_context, operation, attrs, normalized_event, "accepted") do
    ProposedChanges.create_for_manual_intake(
      session_context,
      operation,
      normalized_event,
      attrs
    )
  end

  defp record_durable_acceptance(_session_context, _operation, _normalized_event, "duplicate"),
    do: :ok

  defp record_durable_acceptance(session_context, operation, normalized_event, "accepted") do
    case DurableDelivery.record_and_enqueue(session_context, operation, %{
           event_key: "manual-intake:#{normalized_event.id}:accepted",
           event_kind: "manual_intake.accepted",
           subject_kind: "normalized_intake_event",
           subject_id: normalized_event.id
         }) do
      {:ok, _event} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp create(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}

  defp content_hash(body) do
    :crypto.hash(:sha256, body)
    |> Base.encode16(case: :lower)
  end
end

defmodule OfficeGraph.Integrations.Actions.SubmitManualIntake do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.{CommandError, TypedId}
  alias OfficeGraph.Integrations
  alias OfficeGraph.Integrations.CommandResults.SubmitManualIntake
  alias OfficeGraph.Operations

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, attrs} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :manual_intake_submit,
             idempotency_key,
             attrs
           ),
         {:ok, intake} <- Integrations.submit_manual_intake(session_context, operation, attrs) do
      proposed_change_ids = Enum.map(intake.proposed_changes, & &1.id)

      SubmitManualIntake.new(
        command: "submit_manual_intake",
        operation_id: operation.id,
        normalized_event: intake.normalized_event,
        proposed_changes: intake.proposed_changes,
        affected_ids:
          [
            TypedId.new!(
              type: "normalized_intake_event",
              id: intake.normalized_event.id
            )
          ] ++
            Enum.map(
              proposed_change_ids,
              &TypedId.new!(type: "proposed_graph_change", id: &1)
            )
      )
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
