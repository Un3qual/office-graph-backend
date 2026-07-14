defmodule OfficeGraph.Repo.Migrations.CreateRelationshipRegistry do
  use Ecto.Migration

  def up do
    create table(:relationship_definitions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :text, null: false
      add :family, :text, null: false
      add :direction, :text, null: false
      add :meaning, :text, null: false
      add :lifecycle, :text, null: false, default: "active"
      add :provenance_policy, :text, null: false
      add :authorization_policy, :text, null: false
      add :cycle_policy, :text, null: false
      add :specialization_posture, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:relationship_definitions, [:key],
             name: :relationship_definitions_key_index
           )

    create index(:relationship_definitions, [:lifecycle, :key],
             name: :relationship_definitions_active_key_index,
             where: "lifecycle = 'active'"
           )

    create constraint(:relationship_definitions, :relationship_definitions_direction_valid,
             check: "direction IN ('directed', 'undirected')"
           )

    create constraint(:relationship_definitions, :relationship_definitions_lifecycle_valid,
             check: "lifecycle IN ('active', 'deprecated')"
           )

    create constraint(:relationship_definitions, :relationship_definitions_cycle_policy_valid,
             check: "cycle_policy IN ('allow', 'forbid')"
           )

    create constraint(
             :relationship_definitions,
             :relationship_definitions_specialization_posture_valid,
             check: "specialization_posture IN ('closed', 'registered')"
           )

    create table(:relationship_endpoint_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :relationship_definition_id,
          references(:relationship_definitions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :source_kind, :text, null: false
      add :target_kind, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :relationship_endpoint_rules,
             [:relationship_definition_id, :source_kind, :target_kind],
             name: :relationship_endpoint_rules_definition_kinds_index
           )

    create index(:relationship_endpoint_rules, [:source_kind, :target_kind],
             name: :relationship_endpoint_rules_kinds_index
           )

    execute("""
    INSERT INTO relationship_definitions (
      id,
      key,
      family,
      direction,
      meaning,
      lifecycle,
      provenance_policy,
      authorization_policy,
      cycle_policy,
      specialization_posture,
      inserted_at,
      updated_at
    ) VALUES
      (gen_random_uuid(), 'contained_in', 'containment', 'directed', 'The source item belongs to the target scope item.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'forbid', 'registered', now(), now()),
      (gen_random_uuid(), 'decomposes_to', 'decomposition', 'directed', 'The source item is decomposed into the target work, finding, or check item.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'forbid', 'registered', now(), now()),
      (gen_random_uuid(), 'depends_on', 'dependency', 'directed', 'The source work item depends on the target work item.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'forbid', 'registered', now(), now()),
      (gen_random_uuid(), 'blocked_by', 'blocking', 'directed', 'The source work item is blocked by the target work item.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'forbid', 'registered', now(), now()),
      (gen_random_uuid(), 'generated_from', 'provenance', 'directed', 'The source item was generated from the target source item.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'allow', 'registered', now(), now()),
      (gen_random_uuid(), 'requires_check', 'verification', 'directed', 'The source item requires the target verification check.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'allow', 'registered', now(), now()),
      (gen_random_uuid(), 'satisfied_by', 'requirement_satisfaction', 'directed', 'The source item is satisfied by the target result or evidence.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'allow', 'registered', now(), now()),
      (gen_random_uuid(), 'evidenced_by', 'evidence', 'directed', 'The source item is evidenced by the target evidence or result.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'allow', 'registered', now(), now()),
      (gen_random_uuid(), 'review_finding_for', 'review', 'directed', 'The source review finding applies to the target reviewed item.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'allow', 'registered', now(), now()),
      (gen_random_uuid(), 'discussed_in', 'discussion', 'directed', 'The source item is discussed in the target conversation.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'allow', 'registered', now(), now()),
      (gen_random_uuid(), 'references_external', 'external_reference', 'directed', 'The source item references the target external-reference item.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'allow', 'registered', now(), now()),
      (gen_random_uuid(), 'affects_scope', 'affected_scope', 'directed', 'The source item affects the target scope or scoped resource.', 'active', 'operation_required', 'authorize_scope_and_endpoints', 'allow', 'registered', now(), now())
    """)

    execute("""
    INSERT INTO relationship_endpoint_rules (
      id,
      relationship_definition_id,
      source_kind,
      target_kind,
      inserted_at,
      updated_at
    )
    SELECT gen_random_uuid(), definitions.id, rules.source_kind, rules.target_kind, now(), now()
    FROM (VALUES
      ('contained_in', 'signal', 'initiative'),
      ('contained_in', 'task', 'initiative'),
      ('contained_in', 'review_finding', 'initiative'),
      ('contained_in', 'verification_check', 'initiative'),
      ('contained_in', 'artifact', 'initiative'),
      ('contained_in', 'evidence_item', 'initiative'),
      ('contained_in', 'task', 'workstream'),
      ('decomposes_to', 'signal', 'task'),
      ('decomposes_to', 'task', 'task'),
      ('decomposes_to', 'task', 'review_finding'),
      ('decomposes_to', 'task', 'verification_check'),
      ('decomposes_to', 'requirement', 'task'),
      ('decomposes_to', 'decision', 'task'),
      ('depends_on', 'task', 'task'),
      ('depends_on', 'requirement', 'requirement'),
      ('depends_on', 'work_packet', 'work_packet'),
      ('depends_on', 'run', 'run'),
      ('blocked_by', 'task', 'task'),
      ('blocked_by', 'requirement', 'requirement'),
      ('blocked_by', 'work_packet', 'work_packet'),
      ('blocked_by', 'run', 'run'),
      ('generated_from', 'task', 'signal'),
      ('generated_from', 'review_finding', 'task'),
      ('generated_from', 'verification_check', 'review_finding'),
      ('generated_from', 'evidence_item', 'artifact'),
      ('generated_from', 'artifact', 'evidence_item'),
      ('generated_from', 'work_packet', 'signal'),
      ('generated_from', 'run', 'work_packet'),
      ('generated_from', 'proposal', 'signal'),
      ('requires_check', 'task', 'verification_check'),
      ('requires_check', 'review_finding', 'verification_check'),
      ('requires_check', 'requirement', 'verification_check'),
      ('requires_check', 'decision', 'verification_check'),
      ('satisfied_by', 'task', 'verification_result'),
      ('satisfied_by', 'requirement', 'verification_result'),
      ('satisfied_by', 'verification_check', 'verification_result'),
      ('satisfied_by', 'review_finding', 'verification_result'),
      ('satisfied_by', 'task', 'evidence_item'),
      ('satisfied_by', 'requirement', 'evidence_item'),
      ('evidenced_by', 'task', 'evidence_item'),
      ('evidenced_by', 'review_finding', 'evidence_item'),
      ('evidenced_by', 'verification_check', 'evidence_item'),
      ('evidenced_by', 'run', 'evidence_item'),
      ('evidenced_by', 'verification_check', 'verification_result'),
      ('review_finding_for', 'review_finding', 'task'),
      ('discussed_in', 'signal', 'conversation'),
      ('discussed_in', 'task', 'conversation'),
      ('discussed_in', 'review_finding', 'conversation'),
      ('discussed_in', 'verification_check', 'conversation'),
      ('discussed_in', 'artifact', 'conversation'),
      ('discussed_in', 'evidence_item', 'conversation'),
      ('references_external', 'signal', 'external_reference'),
      ('references_external', 'task', 'external_reference'),
      ('references_external', 'review_finding', 'external_reference'),
      ('references_external', 'verification_check', 'external_reference'),
      ('references_external', 'artifact', 'external_reference'),
      ('references_external', 'evidence_item', 'external_reference'),
      ('affects_scope', 'signal', 'initiative'),
      ('affects_scope', 'task', 'initiative'),
      ('affects_scope', 'review_finding', 'initiative'),
      ('affects_scope', 'verification_check', 'initiative'),
      ('affects_scope', 'proposal', 'initiative'),
      ('affects_scope', 'signal', 'workstream'),
      ('affects_scope', 'task', 'workstream'),
      ('affects_scope', 'proposal', 'workspace')
    ) AS rules(definition_key, source_kind, target_kind)
    JOIN relationship_definitions AS definitions ON definitions.key = rules.definition_key
    """)
  end

  def down do
    drop table(:relationship_endpoint_rules)
    drop table(:relationship_definitions)
  end
end
