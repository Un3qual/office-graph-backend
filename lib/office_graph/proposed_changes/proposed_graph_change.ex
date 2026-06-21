defmodule OfficeGraph.ProposedChanges.ProposedGraphChange do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.ProposedChanges.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "proposed_graph_changes"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "proposed_graph_changes_organization_id_fkey",
                      workspace_id: "proposed_graph_changes_workspace_id_fkey",
                      operation_id: "proposed_graph_changes_operation_id_fkey",
                      normalized_event_id: "proposed_graph_changes_normalized_event_id_fkey"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :normalized_event_id, :uuid, public?: true
    attribute :status, :string, allow_nil?: false, public?: true
    attribute :change_type, :string, allow_nil?: false, public?: true
    attribute :payload, :map, allow_nil?: false, default: %{}, public?: true
    attribute :validation_errors, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :applied_at, :utc_datetime_usec, public?: true

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
        :organization_id,
        :workspace_id,
        :operation_id,
        :normalized_event_id,
        :status,
        :change_type,
        :payload,
        :validation_errors,
        :applied_at
      ]
    end

    update :set_payload do
      accept [:payload]
    end

    update :reject do
      accept [:validation_errors]
      change set_attribute(:status, "rejected")
    end

    update :mark_applied do
      accept [:applied_at]
      change set_attribute(:status, "applied")
    end
  end
end
