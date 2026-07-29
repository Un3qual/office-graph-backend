defmodule OfficeGraph.WorkGraph.ReviewFinding.ValidateOpenTask do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.WorkGraph.Task

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.Changeset.get_attribute(changeset, :task_id) do
        nil ->
          changeset

        task_id ->
          validate_open_task(changeset, task_id)
      end
    end)
  end

  defp validate_open_task(changeset, task_id) do
    Task
    |> Ash.Query.filter(id == ^task_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{lifecycle_state: "open"}} ->
        changeset

      {:ok, nil} ->
        changeset

      {:ok, _completed_or_closed} ->
        Ash.Changeset.add_error(changeset,
          field: :task_id,
          message: "must reference an open task"
        )

      {:error, _error} ->
        # ValidateSameScopeReferences owns lookup failures; this guard only rejects closed tasks.
        changeset
    end
  end
end

defmodule OfficeGraph.WorkGraph.ReviewFinding do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "review_findings"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :graph_item_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :task, OfficeGraph.WorkGraph.Task do
      source_attribute :task_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :body_document, OfficeGraph.Content.Document do
      source_attribute :body_document_id
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

    has_many :verification_checks, OfficeGraph.WorkGraph.VerificationCheck do
      source_attribute :id
      destination_attribute :review_finding_id
      public? true
    end
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, countable: false, required?: false
    end

    read :read_for_proposed_change_replay do
      public? false
    end

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :graph_item_id,
        :task_id,
        :body_document_id,
        :title
      ]

      change set_attribute(:lifecycle_state, "open")

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                graph_item_id:
                  {OfficeGraph.WorkGraph.GraphItem,
                   resource_type: "review_finding", resource_id: :id},
                task_id: OfficeGraph.WorkGraph.Task,
                body_document_id: OfficeGraph.Content.Document
              ]}

      change OfficeGraph.WorkGraph.ReviewFinding.ValidateOpenTask
    end

    action :persist_review_finding_contract, OfficeGraph.WorkGraph.CommandActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.Content.Document,
        OfficeGraph.Content.DocumentBlock,
        OfficeGraph.Content.DocumentRevision,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        OfficeGraph.WorkGraph.GraphItem,
        OfficeGraph.WorkGraph.GraphRelationship,
        OfficeGraph.WorkGraph.RelationshipDefinition,
        OfficeGraph.WorkGraph.RelationshipEndpointRule,
        OfficeGraph.WorkGraph.Task
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :task_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false
      argument :body, :string, allow_nil?: false, default: ""

      run {OfficeGraph.WorkGraph.ProposalCommands, mode: :create_review_finding}
    end

    update :mark_verified_complete do
      public? false
      accept []
      change set_attribute(:lifecycle_state, "verified_complete")
    end
  end

  policies do
    policy action(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action(:read_for_proposed_change_replay) do
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
                    capability: :proposed_change_apply}
    end
  end

  graphql do
    type :review_finding

    paginate_relationship_with(verification_checks: :relay)
  end

  json_api do
    type "review_finding"
  end
end
