defmodule OfficeGraph.Runs.ExecutionObservation do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Runs.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "execution_observations"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_operation: "execution_observations_operation_id_unique_index",
                         unique_source_idempotency_key:
                           "execution_observations_idempotency_key_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :work_run_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :execution_id, :uuid, public?: true
    attribute :context_package_id, :uuid, public?: true
    attribute :step_key, :string, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: true, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: true, public?: true
    attribute :source_kind, :string, allow_nil?: false, public?: true
    attribute :source_identity, :string, allow_nil?: false, public?: true
    attribute :idempotency_key, :string, allow_nil?: true, public?: true
    attribute :observed_status, :string, allow_nil?: false, public?: true
    attribute :normalized_status, :string, allow_nil?: false, public?: true
    attribute :source_recorded_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :ingested_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :freshness_state, :string, allow_nil?: false, public?: true
    attribute :trust_basis, :string, allow_nil?: false, public?: true
    attribute :rationale, :string, allow_nil?: true, public?: true
    attribute :metadata, :map, allow_nil?: false, public?: true, default: %{}

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :work_run, OfficeGraph.Runs.Run do
      source_attribute :work_run_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :verification_check, OfficeGraph.WorkGraph.VerificationCheck do
      source_attribute :verification_check_id
      define_attribute? false
    end

    belongs_to :graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :graph_item_id
      define_attribute? false
    end
  end

  actions do
    defaults [:read]

    create :create do
      public? false

      accept [
        :id,
        :organization_id,
        :workspace_id,
        :work_run_id,
        :operation_id,
        :execution_id,
        :context_package_id,
        :step_key,
        :verification_check_id,
        :graph_item_id,
        :source_kind,
        :source_identity,
        :idempotency_key,
        :observed_status,
        :normalized_status,
        :source_recorded_at,
        :freshness_state,
        :trust_basis,
        :rationale,
        :metadata
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                work_run_id: OfficeGraph.Runs.Run,
                operation_id: OfficeGraph.Operations.OperationCorrelation,
                verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
                graph_item_id: OfficeGraph.WorkGraph.GraphItem
              ]}

      change OfficeGraph.Runs.Changes.DeriveObservationIngestedAt
      change OfficeGraph.Runs.Changes.ValidateObservationRunReferences
    end
  end

  identities do
    identity :unique_operation, [:operation_id]

    identity :unique_source_idempotency_key,
             [:organization_id, :workspace_id, :source_kind, :source_identity, :idempotency_key],
             where: expr(not is_nil(idempotency_key))
  end

  policies do
    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end

    policy action(:create) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :execution_observation_record}
    end
  end

  graphql do
    type :execution_observation
  end

  json_api do
    type "execution_observation"
  end
end
