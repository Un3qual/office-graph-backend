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

  alias OfficeGraph.Authorization
  alias OfficeGraph.Integrations.{ExternalSource, NormalizedIntakeEvent, RawArchive}
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Repo

  def submit_manual_intake(session_context, operation, attrs) do
    with :ok <-
           Authorization.authorize(session_context, :manual_intake_submit,
             organization_id: session_context.organization_id
           ),
         {:ok, intake} <- record_manual_intake(session_context, operation, attrs),
         {:ok, proposed_changes} <-
           ProposedChanges.create_for_manual_intake(
             session_context,
             operation,
             intake.normalized_event,
             attrs
           ) do
      {:ok, Map.put(intake, :proposed_changes, proposed_changes)}
    end
  end

  def record_manual_intake(session_context, operation, attrs) do
    Repo.transaction(fn ->
      source =
        get_or_insert!(
          ExternalSource,
          [key: attrs.source_identity],
          ExternalSource.changeset(%ExternalSource{}, %{
            key: attrs.source_identity,
            name: "Manual Intake",
            kind: "manual"
          })
        )

      duplicate_of =
        Repo.get_by(NormalizedIntakeEvent,
          source_identity: attrs.source_identity,
          replay_identity: attrs.replay_identity,
          outcome: "accepted"
        )

      raw_archive =
        RawArchive.changeset(%RawArchive{}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          source_id: source.id,
          operation_id: operation.id,
          content_hash: content_hash(attrs.body),
          body: attrs.body,
          metadata: %{}
        })
        |> Repo.insert!()

      outcome = if duplicate_of, do: "duplicate", else: "accepted"

      normalized_event =
        NormalizedIntakeEvent.changeset(%NormalizedIntakeEvent{}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          raw_archive_id: raw_archive.id,
          operation_id: operation.id,
          source_identity: attrs.source_identity,
          replay_identity: attrs.replay_identity,
          outcome: outcome,
          duplicate_of_id: duplicate_of && duplicate_of.id
        })
        |> Repo.insert!()

      %{
        raw_archive: raw_archive,
        normalized_event: normalized_event,
        duplicate?: outcome == "duplicate"
      }
    end)
  end

  defp content_hash(body) do
    :crypto.hash(:sha256, body)
    |> Base.encode16(case: :lower)
  end

  defp get_or_insert!(schema, lookup, changeset) do
    Repo.get_by(schema, lookup) || Repo.insert!(changeset)
  end
end
