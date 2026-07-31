defmodule OfficeGraph.Operations.OperationCorrelation do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Operations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "operation_correlations"
    repo OfficeGraph.Repo

    identity_index_names unique_idempotency_key: "operation_correlations_idempotency_key_index",
                         unique_system_organization_idempotency:
                           "operation_correlations_system_organization_idempotency_index",
                         unique_system_workspace_idempotency:
                           "operation_correlations_system_workspace_idempotency_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :operation_kind, :string, allow_nil?: false, default: "human", public?: true
    attribute :action, :string, allow_nil?: false, public?: true
    attribute :correlation_id, :string, allow_nil?: false, public?: true
    attribute :idempotency_key, :string, public?: true
    attribute :authority_basis, :string, public?: true
    attribute :causation_key, :string, public?: true
    attribute :idempotency_scope, :string, public?: true
    attribute :credential_id, :uuid, public?: true
    attribute :subject_kind, :string, public?: true
    attribute :subject_id, :uuid, public?: true
    attribute :subject_version, :integer, public?: true
    attribute :command_input_digest, :string, public?: true
    attribute :system_organization_identity_slot, :string, public?: false, writable?: false
    attribute :system_workspace_identity_slot, :string, public?: false, writable?: false

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :principal, OfficeGraph.Identity.Principal do
      source_attribute :principal_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :session, OfficeGraph.Identity.Session do
      source_attribute :session_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
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
      accept [
        :id,
        :operation_kind,
        :principal_id,
        :session_id,
        :organization_id,
        :workspace_id,
        :action,
        :correlation_id,
        :idempotency_key,
        :authority_basis,
        :causation_key,
        :idempotency_scope,
        :credential_id,
        :subject_kind,
        :subject_id,
        :subject_version,
        :command_input_digest
      ]

      validate present([:authority_basis, :causation_key, :idempotency_scope]),
        where: [attribute_equals(:operation_kind, "system")]

      validate absent(:session_id), where: [attribute_equals(:operation_kind, "system")]

      change set_attribute(:system_organization_identity_slot, nil)
      change set_attribute(:system_workspace_identity_slot, nil)

      change set_attribute(:system_organization_identity_slot, "system") do
        where [attribute_equals(:operation_kind, "system"), absent(:workspace_id)]
      end

      change set_attribute(:system_workspace_identity_slot, "system") do
        where [attribute_equals(:operation_kind, "system"), present(:workspace_id)]
      end
    end
  end

  identities do
    identity :unique_correlation_id, [:organization_id, :workspace_id, :correlation_id],
      field_names: [:correlation_id]

    identity :unique_idempotency_key,
             [
               :organization_id,
               :workspace_id,
               :principal_id,
               :session_id,
               :action,
               :idempotency_key
             ],
             field_names: [:idempotency_key]

    identity :unique_system_organization_idempotency,
             [
               :organization_id,
               :principal_id,
               :system_organization_identity_slot,
               :action,
               :idempotency_scope,
               :idempotency_key
             ],
             field_names: [:idempotency_key]

    identity :unique_system_workspace_idempotency,
             [
               :organization_id,
               :workspace_id,
               :principal_id,
               :system_workspace_identity_slot,
               :action,
               :idempotency_scope,
               :idempotency_key
             ],
             field_names: [:idempotency_key]
  end
end
