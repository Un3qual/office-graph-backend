defmodule OfficeGraph.NodeConversations.CommandResults.StartRunConversation do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :conversation, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.NodeConversations.Conversation]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :start_run_conversation_payload

  def from_result(operation, conversation) do
    new(
      command: "start_run_conversation",
      operation_id: operation.id,
      affected_ids: [TypedId.new!(type: "conversation", id: conversation.id)],
      conversation: conversation
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.NodeConversations.CommandResults.StartRunConversation do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        conversation:
          Map.take(result.conversation, [
            :id,
            :run_id,
            :graph_item_id,
            :created_by_principal_id,
            :operation_id,
            :purpose,
            :visibility,
            :state,
            :state_version,
            :inserted_at,
            :updated_at
          ])
      },
      options
    )
  end
end

defmodule OfficeGraph.NodeConversations.Conversation do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.NodeConversations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "conversations"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_run_graph_item: "conversations_run_graph_item_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :purpose, :string, allow_nil?: false, public?: true
    attribute :visibility, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    attribute :state_version, :integer,
      allow_nil?: false,
      default: 1,
      constraints: [min: 1],
      public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? true
      pagination keyset?: true, countable: false, required?: false
    end

    read :read_for_run_graph_item do
      public? true

      argument :run_id, :uuid, allow_nil?: false, public?: true
      argument :graph_item_id, :uuid, allow_nil?: false, public?: true

      filter expr(
               run_id == ^arg(:run_id) and graph_item_id == ^arg(:graph_item_id) and
                 purpose == "agent_runtime"
             )
    end

    create :create do
      public? false

      accept [
        :id,
        :organization_id,
        :workspace_id,
        :graph_item_id,
        :run_id,
        :created_by_principal_id,
        :operation_id,
        :purpose,
        :visibility,
        :state,
        :state_version
      ]

      validate one_of(:visibility, ~w(run_participants workspace))
      validate one_of(:state, ~w(active closed archived))
    end

    update :set_lifecycle_state do
      public? false
      require_atomic? false
      accept [:state]
      validate one_of(:state, ~w(active closed archived))
      change optimistic_lock(:state_version)
    end

    action :start_run_conversation,
           OfficeGraph.NodeConversations.CommandResults.StartRunConversation do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :run_id, :uuid, allow_nil?: false
      argument :graph_item_id, :uuid, allow_nil?: false

      run fn input, context ->
        OfficeGraph.NodeConversations.Actions.StartRunConversation.run(input, [], context)
      end
    end
  end

  identities do
    identity :unique_run_graph_item, [
      :organization_id,
      :workspace_id,
      :run_id,
      :graph_item_id,
      :purpose
    ]
  end

  relationships do
    belongs_to :graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :graph_item_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :run, OfficeGraph.Runs.Run do
      source_attribute :run_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :created_by_principal, OfficeGraph.Identity.Principal do
      source_attribute :created_by_principal_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    has_many :messages, OfficeGraph.NodeConversations.ConversationMessage do
      destination_attribute :conversation_id
      public? true
    end

    has_many :agent_executions, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :run_id
      destination_attribute :run_id
      filter expr(run_id == parent(run_id) and graph_item_id == parent(graph_item_id))
      public? true
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

  policies do
    policy action(:start_run_conversation) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :conversation_write}
    end

    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end
  end

  graphql do
    type :conversation

    paginate_relationship_with(messages: :relay, agent_executions: :relay)
  end

  json_api do
    type "conversation"
  end
end
