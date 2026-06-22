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

    identity_index_names unique_idempotency_key: "operation_correlations_idempotency_key_index"
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :principal_id, :uuid, allow_nil?: false, public?: true
    attribute :session_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :action, :string, allow_nil?: false, public?: true
    attribute :correlation_id, :string, allow_nil?: false, public?: true
    attribute :idempotency_key, :string, public?: true
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
        :principal_id,
        :session_id,
        :organization_id,
        :workspace_id,
        :action,
        :correlation_id,
        :idempotency_key,
        :metadata
      ]
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
  end
end
