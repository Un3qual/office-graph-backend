defmodule OfficeGraph.WorkGraph.VerificationCheck.ValidateOpenReviewFinding do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.WorkGraph.ReviewFinding

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :review_finding_id) do
      nil ->
        changeset

      review_finding_id ->
        validate_open_review_finding(changeset, review_finding_id)
    end
  end

  defp validate_open_review_finding(changeset, review_finding_id) do
    ReviewFinding
    |> Ash.Query.filter(id == ^review_finding_id)
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
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :review_finding_id, :uuid, allow_nil?: false, public?: true
    attribute :description_document_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

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
                review_finding_id: OfficeGraph.WorkGraph.ReviewFinding,
                description_document_id: OfficeGraph.Content.Document
              ]}

      change OfficeGraph.WorkGraph.VerificationCheck.ValidateOpenReviewFinding
    end

    update :mark_satisfied do
      public? false
      accept []
      change set_attribute(:lifecycle_state, "satisfied")
    end
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
                    capability: :proposed_change_apply}
    end
  end

  graphql do
    type :verification_check
  end

  json_api do
    type "verification_check"
  end
end
