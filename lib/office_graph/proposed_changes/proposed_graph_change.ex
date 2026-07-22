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

    identity_index_names unique_normalized_event_change_type:
                           "proposed_graph_changes_event_type_index"

    foreign_key_names organization_id: "proposed_graph_changes_organization_id_fkey",
                      workspace_id: "proposed_graph_changes_workspace_id_fkey",
                      operation_id: "proposed_graph_changes_operation_id_fkey",
                      applied_operation_id: "proposed_graph_changes_applied_operation_id_fkey",
                      normalized_event_id: "proposed_graph_changes_normalized_event_id_fkey"
  end

  identities do
    identity :unique_normalized_event_change_type, [:normalized_event_id, :change_type],
      where: expr(not is_nil(normalized_event_id))
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :applied_operation_id, :uuid, public?: true
    attribute :applied_resource_id, :uuid, public?: true
    attribute :normalized_event_id, :uuid, public?: true
    attribute :execution_id, :uuid, public?: true
    attribute :context_package_id, :uuid, public?: true
    attribute :step_key, :string, public?: true
    attribute :status, :string, allow_nil?: false, default: "pending", public?: true
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
        :execution_id,
        :context_package_id,
        :step_key,
        :change_type,
        :payload
      ]

      change OfficeGraph.ProposedChanges.ProposedGraphChange.TraceReferenceScope

      change OfficeGraph.ProposedChanges.ProposedGraphChange.ValidateUniqueNormalizedEventChangeType
    end

    update :set_payload do
      require_atomic? false
      accept [:payload]
      validate attribute_equals(:status, "pending")
      change OfficeGraph.ProposedChanges.ProposedGraphChange.ValidatePendingUpdate
    end

    update :reject do
      require_atomic? false
      accept [:validation_errors]
      validate attribute_equals(:status, "pending")
      change OfficeGraph.ProposedChanges.ProposedGraphChange.ValidatePendingUpdate
      change set_attribute(:status, "rejected")
    end

    update :mark_applied do
      require_atomic? false
      accept [:applied_at, :applied_operation_id, :applied_resource_id]
      validate attribute_equals(:status, "pending")
      change OfficeGraph.ProposedChanges.ProposedGraphChange.ValidatePendingUpdate
      change set_attribute(:status, "applied")
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}

      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :proposed_change_apply}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end

    policy action(:create) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :manual_intake_submit}
    end

    policy action(:set_payload) do
      forbid_unless {OfficeGraph.ProposedChanges.ProposedGraphChange.OriginatingOperationActor,
                     action: "manual_intake.submit"}

      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :manual_intake_submit}
    end

    policy action(:reject) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :proposed_change_apply}
    end

    policy action(:mark_applied) do
      forbid_if always()
    end
  end
end
