defmodule OfficeGraph.GitHubIntegration.OutboundAction do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "github_outbound_actions"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_operation: "github_outbound_actions_operation_id_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :installation_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :principal_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :action_kind, :string, allow_nil?: false, public?: true
    attribute :target_type, :string, allow_nil?: false, public?: true
    attribute :target_id, :uuid, allow_nil?: false, public?: true
    attribute :expected_provider_version, :string, allow_nil?: false, public?: true
    attribute :input, :map, allow_nil?: false, default: %{}, public?: false, sensitive?: true
    attribute :state, :string, allow_nil?: false, default: "pending", public?: true
    attribute :provider_response_id, :string, public?: true
    attribute :provider_response_version, :string, public?: true
    attribute :failure_class, :string, public?: true
    attribute :failure_code, :string, public?: true
    attribute :attempted_at, :utc_datetime_usec, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true
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
        :principal_id,
        :organization_id,
        :workspace_id,
        :action_kind,
        :target_type,
        :target_id,
        :expected_provider_version,
        :input
      ]

      change set_attribute(:state, "pending")
      validate one_of(:action_kind, ~w(review_reply check_update))
      public? false
    end

    update :record_result do
      accept [
        :state,
        :provider_response_id,
        :provider_response_version,
        :failure_class,
        :failure_code,
        :attempted_at,
        :completed_at
      ]

      validate one_of(:state, ~w(pending succeeded retryable terminal))
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
