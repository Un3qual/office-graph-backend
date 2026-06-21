defmodule OfficeGraph.Integrations do
  @moduledoc """
  Public boundary for provider adapters and manual intake.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Repo
    ],
    exports: []

  require Ash.Query

  alias OfficeGraph.Authorization
  alias OfficeGraph.Integrations.{ExternalSource, NormalizedIntakeEvent, RawArchive}
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Repo

  def submit_manual_intake(session_context, operation, attrs) do
    with :ok <-
           Authorization.authorize(session_context, :manual_intake_submit,
             organization_id: session_context.organization_id
           ),
         {:ok, intake} <- record_manual_intake(session_context, operation, attrs) do
      if intake.duplicate? do
        {:ok, Map.put(intake, :proposed_changes, [])}
      else
        with {:ok, proposed_changes} <-
               ProposedChanges.create_for_manual_intake(
                 session_context,
                 operation,
                 intake.normalized_event,
                 attrs
               ) do
          {:ok, Map.put(intake, :proposed_changes, proposed_changes)}
        end
      end
    end
  end

  def record_manual_intake(session_context, operation, attrs) do
    Repo.transaction(fn ->
      with {:ok, source} <- get_or_create_source(attrs.source_identity),
           {:ok, duplicate_of} <- accepted_duplicate(attrs),
           outcome = if(duplicate_of, do: "duplicate", else: "accepted"),
           {:ok, raw_archive} <-
             ash_create(RawArchive, %{
               organization_id: session_context.organization_id,
               workspace_id: session_context.workspace_id,
               source_id: source.id,
               operation_id: operation.id,
               content_hash: content_hash(attrs.body),
               body: attrs.body,
               metadata: %{}
             }),
           {:ok, normalized_event} <-
             ash_create(NormalizedIntakeEvent, %{
               organization_id: session_context.organization_id,
               workspace_id: session_context.workspace_id,
               raw_archive_id: raw_archive.id,
               operation_id: operation.id,
               source_identity: attrs.source_identity,
               replay_identity: attrs.replay_identity,
               outcome: outcome,
               duplicate_of_id: duplicate_of && duplicate_of.id
             }) do
        %{
          raw_archive: raw_archive,
          normalized_event: normalized_event,
          duplicate?: outcome == "duplicate"
        }
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  defp content_hash(body) do
    :crypto.hash(:sha256, body)
    |> Base.encode16(case: :lower)
  end

  defp get_or_create_source(source_identity) do
    case Ash.get(ExternalSource, %{key: source_identity},
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, nil} ->
        ash_create(ExternalSource, %{
          key: source_identity,
          name: "Manual Intake",
          kind: "manual"
        })

      {:ok, source} ->
        {:ok, source}

      {:error, error} ->
        {:error, error}
    end
  end

  defp accepted_duplicate(attrs) do
    NormalizedIntakeEvent
    |> Ash.Query.filter(
      source_identity == ^attrs.source_identity and
        replay_identity == ^attrs.replay_identity and
        outcome == "accepted"
    )
    |> Ash.read_one(authorize?: false)
  end

  defp ash_create(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, record, _notifications} -> {:ok, record}
      {:ok, record} -> {:ok, record}
      {:error, error} -> {:error, error}
    end
  end
end
