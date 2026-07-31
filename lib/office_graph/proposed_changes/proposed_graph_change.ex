defmodule OfficeGraph.ProposedChanges.CreationResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false
    field :reason, :term

    field :proposed_changes, {:array, :struct},
      allow_nil?: false,
      constraints: [
        items: [
          instance_of: Module.concat([OfficeGraph, ProposedChanges, ProposedGraphChange])
        ]
      ]
  end

  def created(proposed_changes),
    do: new(status: "created", proposed_changes: proposed_changes)

  def rejected(reason),
    do: new(status: "rejected", reason: reason, proposed_changes: [])

  def to_public_result(%__MODULE__{status: "created", proposed_changes: proposed_changes}),
    do: {:ok, proposed_changes}

  def to_public_result(%__MODULE__{status: "rejected", reason: reason}),
    do: {:error, reason}
end

defmodule OfficeGraph.ProposedChanges.AppliedChangeSet do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false
    field :reason, :term

    field :signal, :struct,
      constraints: [instance_of: Module.concat([OfficeGraph, WorkGraph, Signal])]

    field :task, :struct,
      constraints: [instance_of: Module.concat([OfficeGraph, WorkGraph, Task])]

    field :review_finding, :struct,
      constraints: [instance_of: Module.concat([OfficeGraph, WorkGraph, ReviewFinding])]

    field :verification_check, :struct,
      constraints: [
        instance_of: Module.concat([OfficeGraph, WorkGraph, VerificationCheck])
      ]
  end

  def applied(result) do
    new(
      status: "applied",
      signal: result.signal,
      task: result.task,
      review_finding: result.review_finding,
      verification_check: result.verification_check
    )
  end

  def rejected(reason), do: new(status: "rejected", reason: reason)

  def to_public_result(%__MODULE__{
        status: "applied",
        signal: signal,
        task: task,
        review_finding: review_finding,
        verification_check: verification_check
      }) do
    {:ok,
     %{
       signal: signal,
       task: task,
       review_finding: review_finding,
       verification_check: verification_check
     }}
  end

  def to_public_result(%__MODULE__{status: "rejected", reason: reason}),
    do: {:error, reason}
end

defmodule OfficeGraph.ProposedChanges.ProposedGraphChange do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.ProposedChanges.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "proposed_graph_changes"
    repo OfficeGraph.Repo

    identity_index_names unique_normalized_event_change_type:
                           "proposed_graph_changes_event_type_index"

    foreign_key_names organization_id: "proposed_graph_changes_organization_id_fkey",
                      workspace_id: "proposed_graph_changes_workspace_id_fkey",
                      operation_id: "proposed_graph_changes_operation_id_fkey",
                      applied_operation_id: "proposed_graph_changes_applied_operation_id_fkey",
                      normalized_event_id: "proposed_graph_changes_normalized_event_id_fkey"
  end

  identities do
    identity :unique_normalized_event_change_type, [:normalized_event_id, :change_type]
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :applied_resource_id, :uuid, public?: true
    attribute :step_key, :string, public?: true
    attribute :status, :string, allow_nil?: false, default: "pending", public?: true
    attribute :change_type, :string, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :body, :string, allow_nil?: false, public?: true
    attribute :validation_errors, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :applied_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :applied_operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :applied_operation_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :context_package, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :context_package_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :execution, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :execution_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :normalized_event,
               Module.concat([OfficeGraph, Integrations, NormalizedIntakeEvent]) do
      source_attribute :normalized_event_id
      destination_attribute :id
      attribute_public? true
    end

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

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, countable: false, required?: false
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
        :title,
        :body
      ]

      change OfficeGraph.ProposedChanges.ProposedGraphChange.TraceReferenceScope

      change OfficeGraph.ProposedChanges.ProposedGraphChange.ValidateUniqueNormalizedEventChangeType
    end

    update :set_content do
      require_atomic? false
      accept [:title, :body]
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

    action :create_manual_intake_changes, OfficeGraph.ProposedChanges.CreationResult do
      public? false
      transaction? true

      touches_resources [
        Module.concat([OfficeGraph, Integrations, NormalizedIntakeEvent])
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :normalized_event_id, :uuid, allow_nil?: false
      argument :body, :string, allow_nil?: false, constraints: [trim?: false]

      run {Module.concat([OfficeGraph, ProposedChanges]), mode: :create_manual_intake}
    end

    action :apply_change_set, OfficeGraph.ProposedChanges.AppliedChangeSet do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Authorization.AuthorizationDecision,
        Module.concat([OfficeGraph, WorkGraph, ReviewFinding]),
        Module.concat([OfficeGraph, WorkGraph, Signal]),
        Module.concat([OfficeGraph, WorkGraph, Task]),
        Module.concat([OfficeGraph, WorkGraph, VerificationCheck])
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :normalized_event_id, :uuid
      argument :proposed_change_ids, {:array, :uuid}, allow_nil?: false

      run {Module.concat([OfficeGraph, ProposedChanges]), mode: :apply}
    end

    action :apply_proposed_changes,
           Module.concat([OfficeGraph, ProposedChanges, CommandResults, ApplyProposedChanges]) do
      argument :idempotency_key, :string, allow_nil?: false
      argument :normalized_event_id, :uuid, allow_nil?: false
      argument :proposed_change_ids, {:array, :uuid}, allow_nil?: false

      run {Module.concat([OfficeGraph, ProposedChanges, Actions, ApplyProposedChanges]), []}
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

    policy action(:set_content) do
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

    policy action(:apply_proposed_changes) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :proposed_change_apply}
    end
  end

  graphql do
    type :proposed_graph_change
  end

  json_api do
    type "proposed-graph-change"
  end
end
