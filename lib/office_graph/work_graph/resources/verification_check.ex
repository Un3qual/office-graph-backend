defmodule OfficeGraph.WorkGraph.VerificationCheck.ValidateOpenReviewFinding do
  @moduledoc false

  use Ash.Resource.Change

  require Ash.Query

  @review_finding_resource Module.concat([OfficeGraph, WorkGraph, ReviewFinding])

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.Changeset.get_attribute(changeset, :review_finding_id) do
        nil ->
          changeset

        review_finding_id ->
          validate_open_review_finding(changeset, review_finding_id)
      end
    end)
  end

  defp validate_open_review_finding(changeset, review_finding_id) do
    @review_finding_resource
    |> Ash.Query.filter(id == ^review_finding_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{lifecycle_state: "open"}} ->
        changeset

      {:ok, nil} ->
        changeset

      {:ok, _completed_or_closed} ->
        Ash.Changeset.add_error(changeset,
          field: :review_finding_id,
          message: "must reference an open review finding"
        )

      {:error, _error} ->
        changeset
    end
  end
end

defmodule OfficeGraph.WorkGraph.VerificationCheck do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "verification_checks"
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

    belongs_to :review_finding,
               Module.concat([OfficeGraph, WorkGraph, ReviewFinding]) do
      source_attribute :review_finding_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :description_document, OfficeGraph.Content.Document do
      source_attribute :description_document_id
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

    has_many :evidence_candidates, OfficeGraph.WorkGraph.EvidenceCandidate do
      source_attribute :id
      destination_attribute :verification_check_id
      public? true
    end

    has_many :evidence_items, OfficeGraph.WorkGraph.EvidenceItem do
      source_attribute :id
      destination_attribute :verification_check_id
      public? true
    end

    has_many :verification_results,
             Module.concat([OfficeGraph, WorkGraph, VerificationResult]) do
      source_attribute :id
      destination_attribute :verification_check_id
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
        :review_finding_id,
        :description_document_id,
        :title
      ]

      change set_attribute(:lifecycle_state, "required")

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                graph_item_id:
                  {OfficeGraph.WorkGraph.GraphItem,
                   resource_type: "verification_check", resource_id: :id},
                review_finding_id: Module.concat([OfficeGraph, WorkGraph, ReviewFinding]),
                description_document_id: OfficeGraph.Content.Document
              ]}

      change OfficeGraph.WorkGraph.VerificationCheck.ValidateOpenReviewFinding
    end

    action :persist_verification_check_contract, OfficeGraph.WorkGraph.CommandActionResult do
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
        Module.concat([OfficeGraph, WorkGraph, GraphRelationship]),
        OfficeGraph.WorkGraph.RelationshipDefinition,
        OfficeGraph.WorkGraph.RelationshipEndpointRule,
        Module.concat([OfficeGraph, WorkGraph, ReviewFinding])
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :review_finding_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false
      argument :body, :string, allow_nil?: false, default: ""

      run {Module.concat([OfficeGraph, WorkGraph, ProposalCommands]),
           mode: :create_verification_check}
    end

    action :persist_completion_contract, OfficeGraph.WorkGraph.CommandActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.Content.Document,
        OfficeGraph.Content.DocumentBlock,
        OfficeGraph.Content.DocumentRevision,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        OfficeGraph.WorkGraph.Artifact,
        OfficeGraph.WorkGraph.EvidenceItem,
        OfficeGraph.WorkGraph.GraphItem,
        Module.concat([OfficeGraph, WorkGraph, GraphRelationship]),
        OfficeGraph.WorkGraph.RelationshipDefinition,
        OfficeGraph.WorkGraph.RelationshipEndpointRule,
        Module.concat([OfficeGraph, WorkGraph, ReviewFinding]),
        Module.concat([OfficeGraph, WorkGraph, Task]),
        Module.concat([OfficeGraph, WorkGraph, VerificationResult])
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :verification_check_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false
      argument :body, :string, allow_nil?: false, default: ""
      argument :artifact_uri, :string
      argument :policy_basis, :string
      argument :reason, :string

      run {Module.concat([OfficeGraph, WorkGraph, VerificationCommands]),
           mode: :complete_verification}
    end

    action :persist_evidence_satisfaction_contract,
           OfficeGraph.WorkGraph.CommandActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        Module.concat([OfficeGraph, WorkGraph, ReviewFinding]),
        Module.concat([OfficeGraph, WorkGraph, Task])
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :verification_check_id, :uuid, allow_nil?: false

      run {Module.concat([OfficeGraph, WorkGraph, VerificationCommands]),
           mode: :satisfy_from_evidence}
    end

    update :mark_satisfied do
      public? false
      accept []
      change set_attribute(:lifecycle_state, "satisfied")
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
    type :verification_check

    paginate_relationship_with(
      evidence_candidates: :relay,
      evidence_items: :relay,
      verification_results: :relay
    )
  end

  json_api do
    type "verification_check"
  end
end
