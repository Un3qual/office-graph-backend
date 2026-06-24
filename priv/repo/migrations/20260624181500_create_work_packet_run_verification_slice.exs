defmodule OfficeGraph.Repo.Migrations.CreateWorkPacketRunVerificationSlice do
  use Ecto.Migration

  def change do
    alter table(:work_packets) do
      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict)

      add :current_version_id, :binary_id
    end

    create table(:work_packet_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :work_packet_id, references(:work_packets, type: :binary_id, on_delete: :restrict),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :version_number, :integer, null: false
      add :lifecycle_state, :text, null: false
      add :objective, :text, null: false
      add :context_summary, :text, null: false
      add :requirements, :text, null: false
      add :success_criteria, :text
      add :autonomy_posture, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:work_packet_versions, [:work_packet_id, :version_number])
    create index(:work_packet_versions, [:organization_id, :workspace_id, :lifecycle_state])
    create index(:work_packet_versions, [:operation_id])

    create table(:work_packet_version_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :work_packet_version_id,
          references(:work_packet_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :graph_item_id, references(:graph_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :source_kind, :text, null: false
      add :rationale, :text, null: false
      add :visibility, :text, null: false, default: "full"
      add :sensitivity, :text, null: false, default: "internal"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:work_packet_version_sources, [
             :work_packet_version_id,
             :graph_item_id,
             :source_kind
           ])

    create table(:work_packet_version_required_checks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :work_packet_version_id,
          references(:work_packet_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :verification_check_id,
          references(:verification_checks, type: :binary_id, on_delete: :restrict),
          null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :requirement_kind, :text, null: false, default: "required"
      add :state, :text, null: false, default: "pending"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:work_packet_version_required_checks, [
             :work_packet_version_id,
             :verification_check_id
           ])

    alter table(:runs) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict)
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)

      add :work_packet_version_id,
          references(:work_packet_versions, type: :binary_id, on_delete: :restrict)

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict)

      add :initiator_principal_id, references(:principals, type: :binary_id, on_delete: :restrict)
      add :objective, :text
      add :authority_posture, :text
      add :source_surface, :text
      add :reason, :text
      add :aggregate_state, :text
      add :execution_state, :text
      add :verification_state, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
    end

    create index(:runs, [:organization_id, :workspace_id, :aggregate_state])
    create index(:runs, [:work_packet_version_id])
    create index(:runs, [:operation_id])

    create table(:run_required_checks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false

      add :verification_check_id,
          references(:verification_checks, type: :binary_id, on_delete: :restrict),
          null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :state, :text, null: false, default: "pending"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:run_required_checks, [:run_id, :verification_check_id])

    create table(:execution_observations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :work_run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :verification_check_id,
          references(:verification_checks, type: :binary_id, on_delete: :restrict)

      add :graph_item_id, references(:graph_items, type: :binary_id, on_delete: :restrict)
      add :source_kind, :text, null: false
      add :source_identity, :text, null: false
      add :idempotency_key, :text
      add :observed_status, :text, null: false
      add :normalized_status, :text, null: false
      add :source_recorded_at, :utc_datetime_usec
      add :ingested_at, :utc_datetime_usec, null: false
      add :freshness_state, :text, null: false
      add :trust_basis, :text, null: false
      add :rationale, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :execution_observations,
             [:organization_id, :workspace_id, :source_kind, :source_identity, :idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :execution_observations_idempotency_key_index
           )

    create index(:execution_observations, [:work_run_id, :normalized_status])
    create index(:execution_observations, [:verification_check_id])
    create index(:execution_observations, [:operation_id])

    create table(:evidence_candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :verification_check_id,
          references(:verification_checks, type: :binary_id, on_delete: :restrict),
          null: false

      add :work_run_id, references(:runs, type: :binary_id, on_delete: :restrict)

      add :execution_observation_id,
          references(:execution_observations, type: :binary_id, on_delete: :restrict)

      add :artifact_id, references(:artifacts, type: :binary_id, on_delete: :restrict)

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict), null: false

      add :claim, :text, null: false
      add :source_kind, :text, null: false
      add :source_identity, :text, null: false
      add :freshness_state, :text, null: false
      add :trust_basis, :text, null: false
      add :sensitivity, :text, null: false
      add :candidate_state, :text, null: false
      add :rejection_reason, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:evidence_candidates, [:verification_check_id, :candidate_state])
    create index(:evidence_candidates, [:work_run_id])
    create index(:evidence_candidates, [:execution_observation_id])
    create index(:evidence_candidates, [:operation_id])

    alter table(:evidence_items) do
      add :candidate_id, references(:evidence_candidates, type: :binary_id, on_delete: :restrict)
      add :work_run_id, references(:runs, type: :binary_id, on_delete: :restrict)

      add :accepted_by_principal_id,
          references(:principals, type: :binary_id, on_delete: :restrict)

      add :acceptance_operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict)

      add :acceptance_policy_basis, :text
      add :accepted_at, :utc_datetime_usec
      add :visibility_constraints, :map, null: false, default: %{}
      add :sensitivity, :text
      add :freshness_state, :text
      add :trust_basis, :text
    end

    create unique_index(:evidence_items, [:candidate_id],
             where: "candidate_id IS NOT NULL",
             name: :evidence_items_candidate_id_index
           )

    create index(:evidence_items, [:work_run_id])
    create index(:evidence_items, [:acceptance_operation_id])

    alter table(:verification_results) do
      add :work_run_id, references(:runs, type: :binary_id, on_delete: :restrict)

      add :work_packet_version_id,
          references(:work_packet_versions, type: :binary_id, on_delete: :restrict)

      add :target_graph_item_id, references(:graph_items, type: :binary_id, on_delete: :restrict)
      add :actor_principal_id, references(:principals, type: :binary_id, on_delete: :restrict)
      add :policy_basis, :text
      add :reason, :text
      add :recorded_at, :utc_datetime_usec
    end

    create index(:verification_results, [:work_run_id, :verification_check_id])
    create index(:verification_results, [:work_packet_version_id])
    create index(:verification_results, [:target_graph_item_id])
  end
end
