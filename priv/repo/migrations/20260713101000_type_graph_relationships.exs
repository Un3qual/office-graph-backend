defmodule OfficeGraph.Repo.Migrations.TypeGraphRelationships do
  use Ecto.Migration

  @legacy_relationship_types ~w(
    produced_task
    has_review_finding
    requires_verification
    has_evidence
    references_artifact
  )

  def up do
    reject_unknown_legacy_types!()
    reject_invalid_legacy_endpoints!()
    reject_cross_scope_legacy_edges!()
    reject_missing_legacy_provenance!()

    alter table(:graph_relationships) do
      add :definition_id,
          references(:relationship_definitions, type: :binary_id, on_delete: :restrict)

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict)
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)
      add :lifecycle, :text

      add :asserting_principal_id,
          references(:principals, type: :binary_id, on_delete: :restrict)

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict)

      add :valid_from, :utc_datetime_usec
      add :valid_until, :utc_datetime_usec
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict)

      add :integration_event_id,
          references(:normalized_intake_events, type: :binary_id, on_delete: :restrict)

      add :supersedes_relationship_id,
          references(:graph_relationships, type: :binary_id, on_delete: :restrict)

      add :tombstone_id, references(:tombstones, type: :binary_id, on_delete: :restrict)
    end

    execute("""
    WITH legacy AS (
      SELECT
        relationships.id,
        relationships.relationship_type,
        relationships.source_item_id AS old_source_item_id,
        relationships.target_item_id AS old_target_item_id,
        relationships.inserted_at,
        source_items.organization_id,
        source_items.workspace_id,
        definitions.id AS definition_id,
        provenance.operation_id,
        provenance.actor_principal_id
      FROM graph_relationships AS relationships
      JOIN graph_items AS source_items ON source_items.id = relationships.source_item_id
      JOIN graph_items AS target_items ON target_items.id = relationships.target_item_id
      JOIN relationship_definitions AS definitions
        ON definitions.key = CASE relationships.relationship_type
          WHEN 'produced_task' THEN 'generated_from'
          WHEN 'has_review_finding' THEN 'review_finding_for'
          WHEN 'requires_verification' THEN 'requires_check'
          WHEN 'has_evidence' THEN 'evidenced_by'
          WHEN 'references_artifact' THEN 'generated_from'
        END
      JOIN LATERAL (
        SELECT audit_records.operation_id, audit_records.actor_principal_id
        FROM audit_records
        WHERE audit_records.resource_type = target_items.resource_type
          AND audit_records.resource_id = target_items.resource_id
          AND audit_records.action = CASE relationships.relationship_type
            WHEN 'produced_task' THEN 'task.create'
            WHEN 'has_review_finding' THEN 'review_finding.create'
            WHEN 'requires_verification' THEN 'verification_check.create'
            WHEN 'has_evidence' THEN 'evidence_item.create'
            WHEN 'references_artifact' THEN 'artifact.create'
          END
        ORDER BY audit_records.inserted_at, audit_records.id
        LIMIT 1
      ) AS provenance ON true
    )
    UPDATE graph_relationships AS relationships
    SET
      definition_id = legacy.definition_id,
      source_item_id = CASE
        WHEN legacy.relationship_type IN ('produced_task', 'has_review_finding')
          THEN legacy.old_target_item_id
        ELSE legacy.old_source_item_id
      END,
      target_item_id = CASE
        WHEN legacy.relationship_type IN ('produced_task', 'has_review_finding')
          THEN legacy.old_source_item_id
        ELSE legacy.old_target_item_id
      END,
      organization_id = legacy.organization_id,
      workspace_id = legacy.workspace_id,
      lifecycle = 'active',
      asserting_principal_id = legacy.actor_principal_id,
      operation_id = legacy.operation_id,
      valid_from = legacy.inserted_at,
      valid_until = NULL
    FROM legacy
    WHERE relationships.id = legacy.id
    """)

    execute("""
    ALTER TABLE graph_relationships
      ALTER COLUMN definition_id SET NOT NULL,
      ALTER COLUMN organization_id SET NOT NULL,
      ALTER COLUMN lifecycle SET NOT NULL,
      ALTER COLUMN asserting_principal_id SET NOT NULL,
      ALTER COLUMN operation_id SET NOT NULL,
      ALTER COLUMN valid_from SET NOT NULL
    """)

    drop_if_exists unique_index(
                     :graph_relationships,
                     [:source_item_id, :target_item_id, :relationship_type]
                   )

    alter table(:graph_relationships) do
      remove :relationship_type
    end

    create unique_index(
             :graph_relationships,
             [:organization_id, :definition_id, :source_item_id, :target_item_id],
             name: :graph_relationships_active_definition_edge_index,
             where: "lifecycle = 'active'"
           )

    create index(
             :graph_relationships,
             [:organization_id, :workspace_id, :lifecycle],
             name: :graph_relationships_scope_lifecycle_index
           )

    create index(
             :graph_relationships,
             [:definition_id, :source_item_id, :lifecycle],
             name: :graph_relationships_definition_source_index
           )

    create index(
             :graph_relationships,
             [:definition_id, :target_item_id, :lifecycle],
             name: :graph_relationships_definition_target_index
           )

    create constraint(:graph_relationships, :graph_relationships_lifecycle_valid,
             check: "lifecycle IN ('active', 'superseded', 'archived', 'tombstoned')"
           )

    create constraint(:graph_relationships, :graph_relationships_valid_window_valid,
             check: "valid_until IS NULL OR valid_until >= valid_from"
           )
  end

  def down do
    reject_unrepresentable_typed_edges!()

    alter table(:graph_relationships) do
      add :relationship_type, :text
    end

    execute("""
    WITH typed AS (
      SELECT
        relationships.id,
        relationships.source_item_id AS old_source_item_id,
        relationships.target_item_id AS old_target_item_id,
        definitions.key,
        source_items.resource_type AS source_kind,
        target_items.resource_type AS target_kind
      FROM graph_relationships AS relationships
      JOIN relationship_definitions AS definitions ON definitions.id = relationships.definition_id
      JOIN graph_items AS source_items ON source_items.id = relationships.source_item_id
      JOIN graph_items AS target_items ON target_items.id = relationships.target_item_id
    )
    UPDATE graph_relationships AS relationships
    SET
      relationship_type = CASE
        WHEN typed.key = 'generated_from'
          AND typed.source_kind = 'task'
          AND typed.target_kind = 'signal'
          THEN 'produced_task'
        WHEN typed.key = 'review_finding_for' THEN 'has_review_finding'
        WHEN typed.key = 'requires_check' THEN 'requires_verification'
        WHEN typed.key = 'evidenced_by' THEN 'has_evidence'
        WHEN typed.key = 'generated_from'
          AND typed.source_kind = 'evidence_item'
          AND typed.target_kind = 'artifact'
          THEN 'references_artifact'
      END,
      source_item_id = CASE
        WHEN typed.key = 'generated_from'
          AND typed.source_kind = 'task'
          AND typed.target_kind = 'signal'
          THEN typed.old_target_item_id
        WHEN typed.key = 'review_finding_for' THEN typed.old_target_item_id
        ELSE typed.old_source_item_id
      END,
      target_item_id = CASE
        WHEN typed.key = 'generated_from'
          AND typed.source_kind = 'task'
          AND typed.target_kind = 'signal'
          THEN typed.old_source_item_id
        WHEN typed.key = 'review_finding_for' THEN typed.old_source_item_id
        ELSE typed.old_target_item_id
      END
    FROM typed
    WHERE relationships.id = typed.id
    """)

    execute("ALTER TABLE graph_relationships ALTER COLUMN relationship_type SET NOT NULL")

    drop constraint(:graph_relationships, :graph_relationships_valid_window_valid)
    drop constraint(:graph_relationships, :graph_relationships_lifecycle_valid)

    drop index(:graph_relationships, [], name: :graph_relationships_definition_target_index)

    drop index(:graph_relationships, [], name: :graph_relationships_definition_source_index)

    drop index(:graph_relationships, [], name: :graph_relationships_scope_lifecycle_index)

    drop unique_index(:graph_relationships, [],
           name: :graph_relationships_active_definition_edge_index
         )

    alter table(:graph_relationships) do
      remove :tombstone_id
      remove :supersedes_relationship_id
      remove :integration_event_id
      remove :run_id
      remove :valid_until
      remove :valid_from
      remove :operation_id
      remove :asserting_principal_id
      remove :lifecycle
      remove :workspace_id
      remove :organization_id
      remove :definition_id
    end

    create unique_index(:graph_relationships, [
             :source_item_id,
             :target_item_id,
             :relationship_type
           ])
  end

  defp reject_unknown_legacy_types! do
    accepted = Enum.map_join(@legacy_relationship_types, ", ", &"'#{&1}'")

    execute("""
    DO $$
    DECLARE
      unknown_values text;
    BEGIN
      SELECT string_agg(format('%s (%s)', relationship_type, row_count), ', ' ORDER BY relationship_type)
      INTO unknown_values
      FROM (
        SELECT relationship_type, count(*) AS row_count
        FROM graph_relationships
        WHERE relationship_type NOT IN (#{accepted})
        GROUP BY relationship_type
        ORDER BY relationship_type
        LIMIT 20
      ) AS unknown;

      IF unknown_values IS NOT NULL THEN
        RAISE EXCEPTION 'unknown graph relationship types: %', unknown_values;
      END IF;
    END
    $$
    """)
  end

  defp reject_invalid_legacy_endpoints! do
    execute("""
    DO $$
    DECLARE
      invalid_edges text;
    BEGIN
      SELECT string_agg(
        format('%s:%s->%s', relationships.id, source_items.resource_type, target_items.resource_type),
        ', ' ORDER BY relationships.id
      )
      INTO invalid_edges
      FROM graph_relationships AS relationships
      JOIN graph_items AS source_items ON source_items.id = relationships.source_item_id
      JOIN graph_items AS target_items ON target_items.id = relationships.target_item_id
      WHERE NOT (
        (relationships.relationship_type = 'produced_task'
          AND source_items.resource_type = 'signal'
          AND target_items.resource_type = 'task')
        OR (relationships.relationship_type = 'has_review_finding'
          AND source_items.resource_type = 'task'
          AND target_items.resource_type = 'review_finding')
        OR (relationships.relationship_type = 'requires_verification'
          AND source_items.resource_type = 'review_finding'
          AND target_items.resource_type = 'verification_check')
        OR (relationships.relationship_type = 'has_evidence'
          AND source_items.resource_type = 'verification_check'
          AND target_items.resource_type = 'evidence_item')
        OR (relationships.relationship_type = 'references_artifact'
          AND source_items.resource_type = 'evidence_item'
          AND target_items.resource_type = 'artifact')
      );

      IF invalid_edges IS NOT NULL THEN
        RAISE EXCEPTION 'invalid legacy graph relationship endpoints: %', left(invalid_edges, 2000);
      END IF;
    END
    $$
    """)
  end

  defp reject_cross_scope_legacy_edges! do
    execute("""
    DO $$
    DECLARE
      invalid_count bigint;
    BEGIN
      SELECT count(*)
      INTO invalid_count
      FROM graph_relationships AS relationships
      JOIN graph_items AS source_items ON source_items.id = relationships.source_item_id
      JOIN graph_items AS target_items ON target_items.id = relationships.target_item_id
      WHERE source_items.organization_id <> target_items.organization_id
         OR source_items.workspace_id <> target_items.workspace_id;

      IF invalid_count > 0 THEN
        RAISE EXCEPTION 'legacy graph relationships cross scope: % rows', invalid_count;
      END IF;
    END
    $$
    """)
  end

  defp reject_missing_legacy_provenance! do
    execute("""
    DO $$
    DECLARE
      missing_count bigint;
    BEGIN
      SELECT count(*)
      INTO missing_count
      FROM graph_relationships AS relationships
      JOIN graph_items AS target_items ON target_items.id = relationships.target_item_id
      WHERE NOT EXISTS (
        SELECT 1
        FROM audit_records
        WHERE audit_records.resource_type = target_items.resource_type
          AND audit_records.resource_id = target_items.resource_id
          AND audit_records.action = CASE relationships.relationship_type
            WHEN 'produced_task' THEN 'task.create'
            WHEN 'has_review_finding' THEN 'review_finding.create'
            WHEN 'requires_verification' THEN 'verification_check.create'
            WHEN 'has_evidence' THEN 'evidence_item.create'
            WHEN 'references_artifact' THEN 'artifact.create'
          END
      );

      IF missing_count > 0 THEN
        RAISE EXCEPTION 'legacy graph relationships missing operation provenance: % rows', missing_count;
      END IF;
    END
    $$
    """)
  end

  defp reject_unrepresentable_typed_edges! do
    execute("""
    DO $$
    DECLARE
      invalid_count bigint;
    BEGIN
      SELECT count(*)
      INTO invalid_count
      FROM graph_relationships AS relationships
      JOIN relationship_definitions AS definitions ON definitions.id = relationships.definition_id
      JOIN graph_items AS source_items ON source_items.id = relationships.source_item_id
      JOIN graph_items AS target_items ON target_items.id = relationships.target_item_id
      WHERE relationships.lifecycle <> 'active'
         OR relationships.valid_until IS NOT NULL
         OR relationships.run_id IS NOT NULL
         OR relationships.integration_event_id IS NOT NULL
         OR relationships.supersedes_relationship_id IS NOT NULL
         OR relationships.tombstone_id IS NOT NULL
         OR NOT (
           (definitions.key = 'generated_from'
             AND source_items.resource_type = 'task'
             AND target_items.resource_type = 'signal')
           OR (definitions.key = 'review_finding_for'
             AND source_items.resource_type = 'review_finding'
             AND target_items.resource_type = 'task')
           OR (definitions.key = 'requires_check'
             AND source_items.resource_type = 'review_finding'
             AND target_items.resource_type = 'verification_check')
           OR (definitions.key = 'evidenced_by'
             AND source_items.resource_type = 'verification_check'
             AND target_items.resource_type = 'evidence_item')
           OR (definitions.key = 'generated_from'
             AND source_items.resource_type = 'evidence_item'
             AND target_items.resource_type = 'artifact')
         );

      IF invalid_count > 0 THEN
        RAISE EXCEPTION 'typed graph relationships cannot be rolled back losslessly: % rows', invalid_count;
      END IF;
    END
    $$
    """)
  end
end
