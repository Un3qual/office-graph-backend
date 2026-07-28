defmodule OfficeGraph.Integrations.RawArchive do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Integrations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "raw_archives"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "raw_archives_organization_id_fkey",
                      workspace_id: "raw_archives_workspace_id_fkey",
                      source_id: "raw_archives_source_id_fkey",
                      operation_id: "raw_archives_operation_id_fkey"

    identity_index_names provider_delivery: "raw_archives_provider_delivery_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :content_hash, :string, allow_nil?: false, public?: true
    attribute :archive_kind, :string, allow_nil?: false, default: "manual_intake", public?: true
    attribute :external_delivery_id, :string, public?: true
    attribute :provider_event, :string, public?: true
    attribute :external_installation_id, :integer, public?: true

    attribute :body, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false]

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

    belongs_to :external_source, OfficeGraph.Integrations.ExternalSource do
      source_attribute :source_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      attribute_public? true
    end

    has_many :normalized_events, OfficeGraph.Integrations.NormalizedIntakeEvent do
      source_attribute :id
      destination_attribute :raw_archive_id
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
        :organization_id,
        :workspace_id,
        :source_id,
        :operation_id,
        :content_hash,
        :archive_kind,
        :external_delivery_id,
        :provider_event,
        :external_installation_id,
        :body
      ]
    end
  end

  identities do
    identity :provider_delivery, [:source_id, :external_delivery_id],
      where: expr(not is_nil(external_delivery_id))
  end
end
