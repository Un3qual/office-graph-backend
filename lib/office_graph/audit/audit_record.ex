defmodule OfficeGraph.Audit.AuditRecord do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Audit.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "audit_records"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :actor_principal_id, :uuid, allow_nil?: false, public?: true
    attribute :action, :string, allow_nil?: false, public?: true
    attribute :resource_type, :string, allow_nil?: false, public?: true
    attribute :resource_id, :uuid, allow_nil?: false, public?: true
    attribute :sensitive, :boolean, allow_nil?: false, default: true, public?: true

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
        :operation_id,
        :actor_principal_id,
        :action,
        :resource_type,
        :resource_id,
        :sensitive
      ]
    end
  end
end
