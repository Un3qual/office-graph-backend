defmodule OfficeGraph.GitHubIntegration.SyncOutcome do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "github_sync_outcomes"
    repo OfficeGraph.Repo

    identity_index_names unique_operation: "github_sync_outcomes_operation_id_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

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
    attribute :retry_at, :utc_datetime_usec, public?: true
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
        :failure_code,
        :retry_at
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
        :failure_code,
        :retry_at
      ]

      validate one_of(
                 :state,
                 ~w(reconciled skipped_stale retryable terminal authorization configuration)
               )

      require_atomic? false
      public? false
    end

    action :persist_reconciliation_snapshot, :struct do
      public? false
      transaction? true
      constraints instance_of: __MODULE__

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.DurableDelivery.DomainEvent,
        OfficeGraph.ExternalRefs.ExternalReference,
        Module.concat([OfficeGraph, GitHubIntegration, Installation]),
        OfficeGraph.Integrations.ExternalSource,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        OfficeGraph.SoftwareProving.CheckRun,
        OfficeGraph.SoftwareProving.GitHub.CheckRunExtension,
        OfficeGraph.SoftwareProving.GitHub.PullRequestExtension,
        OfficeGraph.SoftwareProving.GitHub.RepositoryExtension,
        OfficeGraph.SoftwareProving.GitHub.ReviewCommentExtension,
        OfficeGraph.SoftwareProving.GitHub.ReviewThreadExtension,
        OfficeGraph.SoftwareProving.PullRequest,
        OfficeGraph.SoftwareProving.Repository,
        OfficeGraph.SoftwareProving.ReviewComment,
        OfficeGraph.SoftwareProving.ReviewThread,
        OfficeGraph.WorkGraph.GraphItem,
        OfficeGraph.WorkGraph.GraphRelationship,
        OfficeGraph.WorkGraph.Signal
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :installation_id, :uuid, allow_nil?: false
      argument :source_id, :uuid, allow_nil?: false

      argument :request, :struct,
        allow_nil?: false,
        constraints: [instance_of: OfficeGraph.GitHubIntegration.ReconciliationRequest]

      argument :snapshot, :struct,
        allow_nil?: false,
        constraints: [
          instance_of: OfficeGraph.GitHubIntegration.Adapter.ReconciliationSnapshot
        ]

      run {Module.concat([OfficeGraph, GitHubIntegration, Reconciler]), mode: :snapshot}
    end

    action :persist_reconciliation_outcome, :struct do
      public? false
      transaction? true
      constraints instance_of: __MODULE__

      touches_resources [
        Module.concat([OfficeGraph, GitHubIntegration, Installation]),
        OfficeGraph.Operations.OperationCorrelation
      ]

      argument :mode, :string, allow_nil?: false
      argument :operation_id, :uuid, allow_nil?: false
      argument :installation_id, :uuid, allow_nil?: false
      argument :object_type, :string, allow_nil?: false
      argument :object_id, :string, allow_nil?: false
      argument :delivery_id, :string, allow_nil?: false
      argument :state, :string
      argument :failure_class, :string
      argument :failure_code, :string
      argument :retry_at, :utc_datetime_usec
      argument :revoke_installation, :boolean, allow_nil?: false, default: false

      validate argument_in(
                 :mode,
                 ~w(record_failure record_storage_failure finalize_failure pre_operation)
               )

      run {Module.concat([OfficeGraph, GitHubIntegration, Reconciler]), mode: :outcome}
    end
  end

  identities do
    identity :unique_operation, [:operation_id]
  end

  relationships do
    belongs_to :installation, OfficeGraph.GitHubIntegration.Installation do
      source_attribute :installation_id
      destination_attribute :id
      public? true
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      public? true
      attribute_public? true
    end
  end
end
