defmodule OfficeGraph.Repo.Migrations.CreateWalkingSkeletonPersistence do
  use Ecto.Migration

  def change do
    create table(:operation_correlations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :principal_id, references(:principals, type: :binary_id, on_delete: :restrict),
        null: false

      add :session_id, references(:sessions, type: :binary_id, on_delete: :restrict), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :action, :text, null: false
      add :correlation_id, :text, null: false
      add :idempotency_key, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:operation_correlations, [
             :organization_id,
             :workspace_id,
             :correlation_id
           ])

    create index(:operation_correlations, [:organization_id, :workspace_id, :action])

    create table(:authorization_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :principal_id, references(:principals, type: :binary_id, on_delete: :restrict),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :action, :text, null: false
      add :decision, :text, null: false
      add :reason, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:authorization_decisions, [:operation_id])

    create table(:revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :resource_type, :text, null: false
      add :resource_id, :binary_id, null: false
      add :revision_type, :text, null: false
      add :summary, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:revisions, [:resource_type, :resource_id])

    create table(:audit_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :actor_principal_id, references(:principals, type: :binary_id, on_delete: :restrict),
        null: false

      add :action, :text, null: false
      add :resource_type, :text, null: false
      add :resource_id, :binary_id, null: false
      add :sensitive, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:audit_records, [:resource_type, :resource_id])

    create table(:tombstones, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :resource_type, :text, null: false
      add :resource_id, :binary_id, null: false
      add :deleted_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tombstones, [:resource_type, :resource_id])

    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :plain_text, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:document_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false
      add :block_type, :text, null: false
      add :text, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:document_blocks, [:document_id, :position])

    create table(:document_marks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :block_id, references(:document_blocks, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mark_type, :text, null: false
      add :attrs, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:document_references, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_type, :text, null: false
      add :target_id, :binary_id, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:document_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :revision_number, :integer, null: false
      add :semantic_summary, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:document_revisions, [:document_id, :revision_number])

    create table(:graph_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :resource_type, :text, null: false
      add :resource_id, :binary_id, null: false
      add :title, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:graph_items, [:resource_type, :resource_id])
    create index(:graph_items, [:organization_id, :workspace_id])

    create table(:graph_relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :source_item_id, references(:graph_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_item_id, references(:graph_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :relationship_type, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:graph_relationships, [
             :source_item_id,
             :target_item_id,
             :relationship_type
           ])

    create table(:external_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :text, null: false
      add :name, :text, null: false
      add :kind, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:external_sources, [:key])

    create table(:raw_archives, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :source_id, references(:external_sources, type: :binary_id, on_delete: :restrict),
        null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :content_hash, :text, null: false
      add :body, :text, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:raw_archives, [:source_id, :content_hash])

    create table(:normalized_intake_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :raw_archive_id, references(:raw_archives, type: :binary_id, on_delete: :restrict),
        null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :source_identity, :text, null: false
      add :replay_identity, :text, null: false
      add :outcome, :text, null: false

      add :duplicate_of_id,
          references(:normalized_intake_events, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:normalized_intake_events, [:source_identity, :replay_identity])

    create unique_index(
             :normalized_intake_events,
             [:organization_id, :workspace_id, :source_identity, :replay_identity],
             where: "outcome = 'accepted'",
             name: :normalized_intake_events_accepted_replay_identity_index
           )

    create table(:external_references, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :source_id, references(:external_sources, type: :binary_id, on_delete: :restrict),
        null: false

      add :external_id, :text, null: false
      add :resource_type, :text, null: false
      add :resource_id, :binary_id, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:external_references, [:source_id, :external_id])

    create table(:signals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :graph_item_id, references(:graph_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :body_document_id, references(:documents, type: :binary_id, on_delete: :restrict),
        null: false

      add :title, :text, null: false
      add :state, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:signals, [:graph_item_id])

    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :graph_item_id, references(:graph_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :source_signal_id, references(:signals, type: :binary_id, on_delete: :restrict)

      add :body_document_id, references(:documents, type: :binary_id, on_delete: :restrict),
        null: false

      add :title, :text, null: false
      add :lifecycle_state, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tasks, [:graph_item_id])

    create table(:review_findings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :graph_item_id, references(:graph_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :task_id, references(:tasks, type: :binary_id, on_delete: :restrict), null: false

      add :body_document_id, references(:documents, type: :binary_id, on_delete: :restrict),
        null: false

      add :title, :text, null: false
      add :lifecycle_state, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:review_findings, [:graph_item_id])

    create table(:verification_checks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :graph_item_id, references(:graph_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :review_finding_id,
          references(:review_findings, type: :binary_id, on_delete: :restrict), null: false

      add :description_document_id,
          references(:documents, type: :binary_id, on_delete: :restrict), null: false

      add :title, :text, null: false
      add :lifecycle_state, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:verification_checks, [:graph_item_id])

    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :graph_item_id, references(:graph_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :title, :text, null: false
      add :uri, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:artifacts, [:graph_item_id])

    create table(:evidence_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :graph_item_id, references(:graph_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :verification_check_id,
          references(:verification_checks, type: :binary_id, on_delete: :restrict), null: false

      add :artifact_id, references(:artifacts, type: :binary_id, on_delete: :restrict)

      add :body_document_id, references(:documents, type: :binary_id, on_delete: :restrict),
        null: false

      add :title, :text, null: false
      add :state, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:evidence_items, [:graph_item_id])

    create table(:verification_results, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :verification_check_id,
          references(:verification_checks, type: :binary_id, on_delete: :restrict), null: false

      add :evidence_item_id, references(:evidence_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :result, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:verification_results, [:verification_check_id])

    create table(:work_packets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :title, :text, null: false
      add :state, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :work_packet_id, references(:work_packets, type: :binary_id, on_delete: :restrict),
        null: false

      add :state, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:run_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false
      add :event_type, :text, null: false
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:proposed_graph_changes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :normalized_event_id,
          references(:normalized_intake_events, type: :binary_id, on_delete: :restrict)

      add :status, :text, null: false
      add :change_type, :text, null: false
      add :payload, :map, null: false, default: %{}
      add :validation_errors, {:array, :text}, null: false, default: []
      add :applied_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:proposed_graph_changes, [:organization_id, :workspace_id, :status])
  end
end
