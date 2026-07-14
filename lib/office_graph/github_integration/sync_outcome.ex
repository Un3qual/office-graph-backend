defmodule OfficeGraph.GitHubIntegration.SyncOutcome do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "github_sync_outcomes"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_operation: "github_sync_outcomes_operation_id_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :installation_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :object_type, :string, allow_nil?: false, public?: true
    attribute :object_id, :string, allow_nil?: false, public?: true
    attribute :delivery_id, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true
    attribute :provider_version, :string, public?: true
    attribute :provider_sequence, :integer, public?: true
    attribute :resource_type, :string, public?: true
    attribute :resource_id, :uuid, public?: true
    attribute :signal_ids, {:array, :uuid}, allow_nil?: false, default: [], public?: true
    attribute :failure_class, :string, public?: true
    attribute :failure_code, :string, public?: true
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
        :installation_id,
        :operation_id,
        :object_type,
        :object_id,
        :delivery_id,
        :state,
        :provider_version,
        :provider_sequence,
        :resource_type,
        :resource_id,
        :signal_ids,
        :failure_class,
        :failure_code
      ]

      validate one_of(
                 :state,
                 ~w(reconciled skipped_stale retryable terminal authorization configuration)
               )

      public? false
    end

    update :record_result do
      accept [
        :state,
        :provider_version,
        :provider_sequence,
        :resource_type,
        :resource_id,
        :signal_ids,
        :failure_class,
        :failure_code
      ]

      validate one_of(
                 :state,
                 ~w(reconciled skipped_stale retryable terminal authorization configuration)
               )

      require_atomic? false
      public? false
    end
  end

  identities do
    identity :unique_operation, [:operation_id]
  end

  relationships do
    belongs_to :installation, OfficeGraph.GitHubIntegration.Installation do
      source_attribute :installation_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      define_attribute? false
      public? true
    end
  end
end
