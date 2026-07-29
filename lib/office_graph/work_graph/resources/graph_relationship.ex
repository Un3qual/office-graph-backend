defmodule OfficeGraph.WorkGraph.GraphRelationship do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "graph_relationships"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names active_definition_edge:
                           "graph_relationships_active_definition_edge_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :lifecycle, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A(active|superseded|archived|tombstoned)\z/]

    attribute :valid_from, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :valid_until, :utc_datetime_usec, public?: true
    attribute :deleted_at, :utc_datetime_usec, public?: true
    attribute :deletion_reason, :string, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :definition, OfficeGraph.WorkGraph.RelationshipDefinition do
      source_attribute :definition_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :governing_workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      attribute_public? true
    end

    belongs_to :source_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :source_item_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :target_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :target_item_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :asserting_principal, OfficeGraph.Identity.Principal do
      source_attribute :asserting_principal_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :superseded_relationship, __MODULE__ do
      source_attribute :supersedes_relationship_id
      attribute_public? true
    end

    belongs_to :deletion_operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :deletion_operation_id
      attribute_public? true
    end

    belongs_to :deleted_by_principal, OfficeGraph.Identity.Principal do
      source_attribute :deleted_by_principal_id
      attribute_public? true
    end

    belongs_to :integration_event,
               Module.concat([OfficeGraph, Integrations, NormalizedIntakeEvent]) do
      source_attribute :integration_event_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :run, Module.concat([OfficeGraph, Runs, Run]) do
      source_attribute :run_id
      destination_attribute :id
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :definition_id,
        :organization_id,
        :workspace_id,
        :source_item_id,
        :target_item_id,
        :asserting_principal_id,
        :operation_id,
        :valid_from,
        :run_id,
        :integration_event_id,
        :supersedes_relationship_id
      ]

      change OfficeGraph.WorkGraph.Changes.ValidateRelationshipEndpoints
      change set_attribute(:lifecycle, "active")
      change set_attribute(:valid_until, nil)
    end

    action :persist_create_contract, OfficeGraph.WorkGraph.CommandActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        Module.concat([OfficeGraph, Integrations, NormalizedIntakeEvent]),
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        Module.concat([OfficeGraph, Runs, Run]),
        OfficeGraph.WorkGraph.GraphItem,
        OfficeGraph.WorkGraph.RelationshipDefinition,
        OfficeGraph.WorkGraph.RelationshipEndpointRule
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :definition_key, :string, allow_nil?: false
      argument :source_item_id, :uuid, allow_nil?: false
      argument :target_item_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid
      argument :valid_from, :utc_datetime_usec
      argument :run_id, :uuid
      argument :integration_event_id, :uuid

      run {Module.concat([OfficeGraph, WorkGraph, RelationshipCommands]), mode: :create}
    end

    action :persist_system_create_contract, OfficeGraph.WorkGraph.CommandActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        Module.concat([OfficeGraph, Integrations, NormalizedIntakeEvent]),
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        Module.concat([OfficeGraph, Runs, Run]),
        OfficeGraph.WorkGraph.GraphItem,
        OfficeGraph.WorkGraph.RelationshipDefinition,
        OfficeGraph.WorkGraph.RelationshipEndpointRule
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :definition_key, :string, allow_nil?: false
      argument :source_item_id, :uuid, allow_nil?: false
      argument :target_item_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid
      argument :valid_from, :utc_datetime_usec
      argument :run_id, :uuid
      argument :integration_event_id, :uuid

      run {Module.concat([OfficeGraph, WorkGraph, RelationshipCommands]), mode: :create_system}
    end

    action :persist_supersede_contract, OfficeGraph.WorkGraph.CommandActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        Module.concat([OfficeGraph, Integrations, NormalizedIntakeEvent]),
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        Module.concat([OfficeGraph, Runs, Run]),
        OfficeGraph.WorkGraph.GraphItem,
        OfficeGraph.WorkGraph.RelationshipDefinition,
        OfficeGraph.WorkGraph.RelationshipEndpointRule
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :relationship_id, :uuid, allow_nil?: false
      argument :definition_key, :string, allow_nil?: false
      argument :source_item_id, :uuid, allow_nil?: false
      argument :target_item_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid
      argument :valid_from, :utc_datetime_usec
      argument :run_id, :uuid
      argument :integration_event_id, :uuid

      run {Module.concat([OfficeGraph, WorkGraph, RelationshipCommands]), mode: :supersede}
    end

    action :persist_archive_contract, OfficeGraph.WorkGraph.CommandActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        OfficeGraph.WorkGraph.GraphItem,
        OfficeGraph.WorkGraph.RelationshipDefinition,
        OfficeGraph.WorkGraph.RelationshipEndpointRule
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :relationship_id, :uuid, allow_nil?: false

      run {Module.concat([OfficeGraph, WorkGraph, RelationshipCommands]), mode: :archive}
    end

    action :persist_restore_contract, OfficeGraph.WorkGraph.CommandActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        Module.concat([OfficeGraph, Integrations, NormalizedIntakeEvent]),
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        Module.concat([OfficeGraph, Runs, Run]),
        OfficeGraph.WorkGraph.GraphItem,
        OfficeGraph.WorkGraph.RelationshipDefinition,
        OfficeGraph.WorkGraph.RelationshipEndpointRule
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :relationship_id, :uuid, allow_nil?: false
      argument :valid_from, :utc_datetime_usec

      run {Module.concat([OfficeGraph, WorkGraph, RelationshipCommands]), mode: :restore}
    end

    update :mark_superseded do
      public? false
      accept [:operation_id, :asserting_principal_id]
      change set_attribute(:lifecycle, "superseded")
      change set_attribute(:valid_until, &DateTime.utc_now/0)
    end

    update :archive do
      public? false
      accept [:operation_id, :asserting_principal_id]
      change set_attribute(:lifecycle, "archived")
      change set_attribute(:valid_until, &DateTime.utc_now/0)
    end

    update :tombstone do
      public? false

      accept [
        :operation_id,
        :asserting_principal_id,
        :deletion_operation_id,
        :deleted_by_principal_id,
        :deletion_reason
      ]

      change set_attribute(:lifecycle, "tombstoned")
      change set_attribute(:valid_until, &DateTime.utc_now/0)
      change set_attribute(:deleted_at, &DateTime.utc_now/0)
    end

    update :restore do
      public? false
      accept [:operation_id, :asserting_principal_id, :valid_from]
      change set_attribute(:lifecycle, "active")
      change set_attribute(:valid_until, nil)
      change set_attribute(:deletion_operation_id, nil)
      change set_attribute(:deleted_by_principal_id, nil)
      change set_attribute(:deleted_at, nil)
      change set_attribute(:deletion_reason, nil)
    end
  end

  identities do
    identity :active_definition_edge,
             [:organization_id, :definition_id, :source_item_id, :target_item_id],
             where: expr(lifecycle == "active")
  end
end
