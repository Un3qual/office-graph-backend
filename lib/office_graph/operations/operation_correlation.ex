defmodule OfficeGraph.Operations.OperationCorrelation do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Operations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "operation_correlations"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_idempotency_key: "operation_correlations_idempotency_key_index",
                         unique_system_idempotency:
                           "operation_correlations_system_scoped_idempotency_index"
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :operation_kind, :string, allow_nil?: false, default: "human", public?: true
    attribute :principal_id, :uuid, allow_nil?: false, public?: true
    attribute :session_id, :uuid, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
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
    attribute :metadata, :map, allow_nil?: false, default: %{}, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
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
        :metadata
      ]

      validate present([:authority_basis, :causation_key, :idempotency_scope]),
        where: [attribute_equals(:operation_kind, "system")]

      validate absent(:session_id), where: [attribute_equals(:operation_kind, "system")]
    end
  end

  identities do
    identity :unique_correlation_id, [:organization_id, :workspace_id, :correlation_id]

    identity :unique_idempotency_key,
             [
               :organization_id,
               :workspace_id,
               :principal_id,
               :session_id,
               :action,
               :idempotency_key
             ],
             where: expr(not is_nil(idempotency_key))

    identity :unique_system_idempotency,
             [
               :organization_id,
               :workspace_id,
               :principal_id,
               :action,
               :idempotency_scope,
               :idempotency_key
             ],
             where: expr(operation_kind == "system"),
             nils_distinct?: false
  end
end
