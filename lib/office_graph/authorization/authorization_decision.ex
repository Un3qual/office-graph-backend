defmodule OfficeGraph.Authorization.AuthorizationDecision do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Authorization.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "authorization_decisions"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :action, :string, allow_nil?: false, public?: true
    attribute :decision, :string, allow_nil?: false, public?: true
    attribute :reason, :string, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

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
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :operation_id, :principal_id, :organization_id, :action, :decision, :reason]
    end
  end
end
