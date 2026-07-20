defmodule OfficeGraph.Repo.Migrations.AddSystemOperationDelivery do
  use Ecto.Migration

  def up do
    alter table(:operation_correlations) do
      add :operation_kind, :text, null: false, default: "human"
      add :authority_basis, :text
      add :causation_key, :text
      add :idempotency_scope, :text
      add :credential_id, :binary_id
      add :subject_kind, :text
      add :subject_id, :binary_id
      add :subject_version, :integer
    end

    execute("ALTER TABLE operation_correlations ALTER COLUMN session_id DROP NOT NULL")
    execute("ALTER TABLE operation_correlations ALTER COLUMN workspace_id DROP NOT NULL")

    create constraint(:operation_correlations, :operation_correlations_kind_valid,
             check: "operation_kind IN ('human', 'system')"
           )

    create constraint(
             :operation_correlations,
             :operation_correlations_human_context_required,
             check: """
             operation_kind <> 'human' OR (
               session_id IS NOT NULL AND
               workspace_id IS NOT NULL AND
               authority_basis IS NULL AND
               causation_key IS NULL AND
               idempotency_scope IS NULL AND
               credential_id IS NULL AND
               subject_kind IS NULL AND
               subject_id IS NULL AND
               subject_version IS NULL
             )
             """
           )

    create constraint(
             :operation_correlations,
             :operation_correlations_system_context_required,
             check: """
             operation_kind <> 'system' OR (
               session_id IS NULL AND
               authority_basis IS NOT NULL AND
               btrim(authority_basis) <> '' AND
               causation_key IS NOT NULL AND
               btrim(causation_key) <> '' AND
               idempotency_scope IS NOT NULL AND
               btrim(idempotency_scope) <> '' AND
               idempotency_key IS NOT NULL AND
               btrim(idempotency_key) <> ''
             )
             """
           )

    create constraint(:operation_correlations, :operation_correlations_subject_complete,
             check: """
             (subject_kind IS NULL AND subject_id IS NULL AND subject_version IS NULL) OR
             (subject_kind IS NOT NULL AND subject_id IS NOT NULL AND
               (subject_version IS NULL OR subject_version > 0))
             """
           )

    create unique_index(
             :operation_correlations,
             [
               :organization_id,
               :principal_id,
               :action,
               :idempotency_scope,
               :idempotency_key
             ],
             where: "operation_kind = 'system'",
             name: :operation_correlations_system_idempotency_index
           )

    create unique_index(:operation_correlations, [:organization_id, :correlation_id],
             where: "operation_kind = 'system'",
             name: :operation_correlations_system_correlation_index
           )

    alter table(:domain_events) do
      add :operation_kind, :text, null: false, default: "human"
      add :event_scope, :text, null: false, default: "workspace"
    end

    execute("ALTER TABLE domain_events ALTER COLUMN workspace_id DROP NOT NULL")
    execute("ALTER TABLE domain_events ALTER COLUMN subject_kind DROP NOT NULL")
    execute("ALTER TABLE domain_events ALTER COLUMN subject_id DROP NOT NULL")
    execute("ALTER TABLE domain_events ALTER COLUMN subject_version DROP NOT NULL")

    create constraint(:domain_events, :domain_events_operation_kind_valid,
             check: "operation_kind IN ('human', 'system')"
           )

    create constraint(:domain_events, :domain_events_scope_valid,
             check: "event_scope IN ('organization', 'workspace')"
           )

    create constraint(:domain_events, :domain_events_workspace_context_required,
             check: """
             operation_kind <> 'human' OR (
               event_scope = 'workspace' AND
               workspace_id IS NOT NULL AND
               subject_kind IS NOT NULL AND
               subject_id IS NOT NULL AND
               subject_version IS NOT NULL
             )
             """
           )

    create constraint(:domain_events, :domain_events_system_scope_consistent,
             check: """
             operation_kind <> 'system' OR (
               (event_scope = 'organization' AND workspace_id IS NULL) OR
               (event_scope = 'workspace' AND workspace_id IS NOT NULL)
             )
             """
           )

    create constraint(:domain_events, :domain_events_subject_complete,
             check: """
             (subject_kind IS NULL AND subject_id IS NULL AND subject_version IS NULL) OR
             (subject_kind IS NOT NULL AND subject_id IS NOT NULL AND
               (subject_version IS NULL OR subject_version > 0))
             """
           )

    execute("""
    INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'system.conformance', 'system.conformance', now(), now())
    ON CONFLICT (key) DO NOTHING
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM operation_correlations WHERE operation_kind = 'system') OR
         EXISTS (SELECT 1 FROM domain_events WHERE operation_kind = 'system') THEN
        RAISE EXCEPTION 'cannot remove system operation delivery while system records exist';
      END IF;
    END
    $$
    """)

    drop_if_exists index(:operation_correlations, [],
                     name: :operation_correlations_system_correlation_index
                   )

    drop_if_exists index(:operation_correlations, [],
                     name: :operation_correlations_system_idempotency_index
                   )

    drop constraint(:domain_events, :domain_events_subject_complete)
    drop constraint(:domain_events, :domain_events_system_scope_consistent)
    drop constraint(:domain_events, :domain_events_workspace_context_required)
    drop constraint(:domain_events, :domain_events_scope_valid)
    drop constraint(:domain_events, :domain_events_operation_kind_valid)

    execute("ALTER TABLE domain_events ALTER COLUMN workspace_id SET NOT NULL")
    execute("ALTER TABLE domain_events ALTER COLUMN subject_kind SET NOT NULL")
    execute("ALTER TABLE domain_events ALTER COLUMN subject_id SET NOT NULL")
    execute("ALTER TABLE domain_events ALTER COLUMN subject_version SET NOT NULL")

    alter table(:domain_events) do
      remove :event_scope
      remove :operation_kind
    end

    drop constraint(:operation_correlations, :operation_correlations_subject_complete)
    drop constraint(:operation_correlations, :operation_correlations_system_context_required)
    drop constraint(:operation_correlations, :operation_correlations_human_context_required)
    drop constraint(:operation_correlations, :operation_correlations_kind_valid)

    execute("ALTER TABLE operation_correlations ALTER COLUMN session_id SET NOT NULL")
    execute("ALTER TABLE operation_correlations ALTER COLUMN workspace_id SET NOT NULL")

    alter table(:operation_correlations) do
      remove :subject_version
      remove :subject_id
      remove :subject_kind
      remove :credential_id
      remove :idempotency_scope
      remove :causation_key
      remove :authority_basis
      remove :operation_kind
    end
  end
end
