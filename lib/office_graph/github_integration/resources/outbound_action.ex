defmodule OfficeGraph.GitHubIntegration.CommandResults.OutboundAction do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :action, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.GitHubIntegration.OutboundAction]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :github_outbound_action_payload

  def from_result(command, operation, action) do
    new(
      command: command,
      operation_id: operation.id,
      affected_ids: [TypedId.new!(type: "github_outbound_action", id: action.id)],
      action: action
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.GitHubIntegration.CommandResults.OutboundAction do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        action:
          Map.take(result.action, [
            :id,
            :installation_id,
            :action_kind,
            :target_type,
            :target_id,
            :expected_provider_version,
            :state,
            :provider_response_id,
            :provider_response_version,
            :failure_class,
            :failure_code
          ])
      },
      options
    )
  end
end

defmodule OfficeGraph.GitHubIntegration.OutboundAction do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "github_outbound_actions"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_operation: "github_outbound_actions_operation_id_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :action_kind, :string, allow_nil?: false, public?: true
    attribute :target_type, :string, allow_nil?: false, public?: true
    attribute :target_id, :uuid, allow_nil?: false, public?: true
    attribute :target_node_id, :string, allow_nil?: false, public?: false
    attribute :expected_provider_version, :string, allow_nil?: false, public?: true

    attribute :reply_body, :string,
      constraints: [trim?: false],
      public?: false,
      sensitive?: true

    attribute :check_status, :string, public?: false
    attribute :check_conclusion, :string, public?: false
    attribute :details_url, :string, public?: false
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
      public? true
      pagination keyset?: true, countable: false, required?: false
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
        :target_node_id,
        :expected_provider_version,
        :reply_body,
        :check_status,
        :check_conclusion,
        :details_url
      ]

      change set_attribute(:state, "pending")
      validate one_of(:action_kind, ~w(review_reply check_update))
      validate present(:reply_body), where: [attribute_equals(:action_kind, "review_reply")]

      validate absent([:check_status, :check_conclusion, :details_url]),
        where: [attribute_equals(:action_kind, "review_reply")]

      validate present([:check_status, :details_url]),
        where: [attribute_equals(:action_kind, "check_update")]

      validate absent(:reply_body), where: [attribute_equals(:action_kind, "check_update")]
      validate one_of(:check_status, ~w(queued in_progress completed))
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

    action :persist_outbound_contract, :struct do
      public? false
      transaction? true
      constraints instance_of: __MODULE__

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.GitHubIntegration.Installation,
        OfficeGraph.GitHubIntegration.PermissionEntry,
        OfficeGraph.GitHubIntegration.SyncOutcome,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        OfficeGraph.SoftwareProving.CheckRun,
        OfficeGraph.SoftwareProving.GitHub.CheckRunExtension,
        OfficeGraph.SoftwareProving.GitHub.ReviewCommentExtension,
        OfficeGraph.SoftwareProving.ReviewComment
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :installation_id, :uuid, allow_nil?: false
      argument :action_kind, :string, allow_nil?: false
      argument :review_comment_id, :uuid
      argument :check_run_id, :uuid
      argument :body, :string, constraints: [trim?: false]
      argument :status, :string
      argument :conclusion, :string
      argument :details_url, :string
      argument :expected_provider_version, :string, allow_nil?: false

      validate argument_in(:action_kind, ~w(review_reply check_update))
      run {OfficeGraph.GitHubIntegration.OutboundCommands, mode: :persist}
    end

    action :persist_revoked_outcome, :struct do
      public? false
      transaction? true
      constraints instance_of: __MODULE__

      touches_resources [
        OfficeGraph.GitHubIntegration.Installation,
        OfficeGraph.Operations.OperationCorrelation
      ]

      argument :action_id, :uuid, allow_nil?: false
      argument :operation_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid
      argument :state, :string
      argument :failure_class, :string
      argument :failure_code, :string
      argument :attempted_at, :utc_datetime_usec
      argument :completed_at, :utc_datetime_usec

      run {OfficeGraph.GitHubIntegration.OutboundWorker, mode: :revoked_outcome}
    end

    action :ensure_outbound_trace, :boolean do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision
      ]

      argument :action_id, :uuid, allow_nil?: false
      argument :operation_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid
      argument :state, :string, allow_nil?: false

      validate argument_in(:state, ~w(succeeded terminal))
      run {OfficeGraph.GitHubIntegration.OutboundWorker, mode: :trace}
    end

    action :reply_to_github_review,
           OfficeGraph.GitHubIntegration.CommandResults.OutboundAction do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :installation_id, :uuid, allow_nil?: false
      argument :review_comment_id, :uuid, allow_nil?: false

      argument :body, :string,
        allow_nil?: false,
        constraints: [trim?: false, match: ~r/\S/]

      argument :expected_provider_version, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      run fn input, context ->
        OfficeGraph.GitHubIntegration.Actions.ReplyToReview.run(input, [], context)
      end
    end

    action :update_github_check,
           OfficeGraph.GitHubIntegration.CommandResults.OutboundAction do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :installation_id, :uuid, allow_nil?: false
      argument :check_run_id, :uuid, allow_nil?: false
      argument :status, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :conclusion, :string
      argument :details_url, :string, allow_nil?: false, constraints: [match: ~r/\S/]

      argument :expected_provider_version, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      run fn input, context ->
        OfficeGraph.GitHubIntegration.Actions.UpdateCheck.run(input, [], context)
      end
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

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      attribute_public? true
    end
  end

  policies do
    policy action(:reply_to_github_review) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :github_review_reply}
    end

    policy action(:update_github_check) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :github_check_update}
    end

    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       (is_nil(workspace_id) or workspace_id == ^actor(:workspace_id))
                   )
    end
  end

  graphql do
    type :github_outbound_action
  end

  json_api do
    type "github_outbound_action"
  end
end
